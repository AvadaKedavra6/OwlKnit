--[[
				Owl - Flags
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local DSS = game:GetService("DataStoreService")
local MS = game:GetService("MessagingService")

--

local IsServer = RunService:IsServer()

--

local Signal = require(script.Parent.Parent.Libs.Signal)
local Trove = require(script.Parent.Parent.Libs.Trove)
local OwlShared = require(script.Parent.OwlShared)
local Log = OwlShared.Logger("Flags")

--

local Topic = "OwlFlags_Sync"
local StoreName = "OwlFlags_v1"
local RegistryKey = "Registry"

local PublishCooldown = 3
local FlushInterval = 1
local FallbackPollInterval = 30
local MaxRetries = 3
local RetryDelay = 2

--

local _flags: {[string]: FlagState} = {}
local _dirty: {[string]: boolean} = {}
local _lastPublish: {[string]: number} = {}
local _store: DataStore? = nil
local _subscribed = false
local _bootstrapped = false
local _trove = Trove.new()

--

local OwlFlag = {}
OwlFlag.Changed = Signal.new() :: any

-- > // Types \\ < --

export type FlagScope = "Public" | "Private" | "Shared"

--

export type FlagState = {
	Name: string,
	Scope: FlagScope,
	Enabled: boolean,
	RolloutPercent: number,
	Whitelist: {[number]: boolean},
	Blacklist: {[number]: boolean},
	UpdatedAt: number,
	Version: number,
}

--

export type FlagConfig = {
	Scope: FlagScope?,
	Enabled: boolean?,
	RolloutPercent: number?,
	Whitelist: {number}?,
	Blacklist: {number}?,
}

--

type SyncMessage = {
	Type: "Update" | "Delete",
	Name: string,
	State: FlagState?,
}

-- > // Func : Stable Hash \\ < --

local function stableHash(flagName: string, userId: number): number
    local str = flagName .. "_" .. tostring(userId)
    local hash = 5381

    for i = 1, #str do
        hash = (hash * 33 + string.byte(str, i)) % 1000000007
    end

    return hash % 100
end

-- > // Func : Default State \\ < --

local function defaultState(name: string, config: FlagConfig?): FlagState
	local whitelist: {[number]: boolean} = {}
	local blacklist: {[number]: boolean} = {}
 
	if config and config.Whitelist then
		for _, id in ipairs(config.Whitelist) do 
            whitelist[id] = true 
        end
	end
 
	if config and config.Blacklist then
		for _, id in ipairs(config.Blacklist) do 
            blacklist[id] = true 
        end
	end
 
	return {
		Name = name,
		Scope = (config and config.Scope) or "Private",
		Enabled = (config and config.Enabled) or false,
		RolloutPercent = math.clamp((config and config.RolloutPercent) or 0, 0, 100),
		Whitelist = whitelist,
		Blacklist = blacklist,
		UpdatedAt = os.time(),
		Version = 1,
	}
end

-- > // Func : Persist Registry \\ < --

local function persistRegistry(): boolean
	if not _store then return false end
 
	local ok, err = pcall(function()
		(_store :: DataStore):UpdateAsync(RegistryKey, function()
			return _flags
		end)
	end)
 
	if not ok then
		Log.warn("Failed to persist flag registry: %s", tostring(err))
	end
 
	return ok
end

-- > // Func : Publish Flag \\ < --

local function publishFlag(name: string, state: FlagState?)
	local now = os.clock()
	local last = _lastPublish[name] or 0
 
	if now - last < PublishCooldown then
		return
	end
 
	_lastPublish[name] = now
 
	local message: SyncMessage = {
		Type = if state then "Update" else "Delete",
		Name = name,
		State = state,
	}
 
	local ok, err = pcall(function()
		MS:PublishAsync(Topic, message)
	end)
 
	if not ok then
		Log.warn("PublishAsync failed for flag %q (will rely on fallback polling): %s", name, tostring(err))
		return
	end
 
	_dirty[name] = nil
end
 
-- > // Func : Flush Loop \\ < --

local function startFlushLoop()
	_trove:Add(task.spawn(function()
		while true do
			task.wait(FlushInterval)
 
			for name in pairs(_dirty) do
				publishFlag(name, _flags[name])
			end
		end
	end))
end

-- > // Func : Fallback Poll loop \\ < --

local function startFallbackPoll()
	_trove:Add(task.spawn(function()
		while true do
			task.wait(FallbackPollInterval)
			if not _store then continue end
 
			local ok, data = pcall(function()
				return (_store :: DataStore):GetAsync(RegistryKey)
			end)
 
			if ok and type(data) == "table" then
				for name, state in pairs(data :: {[string]: FlagState}) do
					local existing = _flags[name]
 
					if not existing or (state.Version or 0) > (existing.Version or 0) then
						_flags[name] = state
						OwlFlag.Changed:Fire(name, state)
					end
				end
			elseif not ok then
				Log.warn("Fallback poll failed: %s", tostring(data))
			end
		end
	end))
end

-- > // Func : On Message \\ < --

local function onMessage(payload: {Data: SyncMessage})
	local message = payload.Data
	if type(message) ~= "table" or type(message.Name) ~= "string" then 
        return 
    end
 
	if message.Type == "Delete" then
		_flags[message.Name] = nil
		OwlFlag.Changed:Fire(message.Name, nil)
		Log.info("Flag %q deleted (synced).", message.Name)
		return
	end
 
	local incoming = message.State
	if not incoming then return end
 
	local existing = _flags[message.Name]
 
	if existing and (existing.Version or 0) >= (incoming.Version or 0) then
		return
	end
 
	_flags[message.Name] = incoming
	OwlFlag.Changed:Fire(message.Name, incoming)
	Log.info("Flag %q synced (v%d).", message.Name, incoming.Version)
end

-- > // Func : Bootstrap \\ < --

function OwlFlag.Bootstrap()
	assert(IsServer, "[Owl - Flags] Bootstrap can only be called on the server.")
	if _bootstrapped then return end
	_bootstrapped = true
 
	local ok, store = pcall(function()
		return DSS:GetDataStore(StoreName)
	end)
 
	if ok then
		_store = store
	else
		Log.warn("Could not access DataStore %q, flags will not persist across restarts.", StoreName)
	end
 
	if _store then
		for attempt = 1, MaxRetries do
			local loadOk, data = pcall(function()
				return (_store :: DataStore):GetAsync(RegistryKey)
			end)
 
			if loadOk then
				if type(data) == "table" then
					_flags = data :: {[string]: FlagState}

					Log.info("Loaded %d flag(s) from DataStore.", (function()
						local c = 0
						for _ in pairs(_flags) do c += 1 end
						return c
					end)())
				end

				break
			else
				Log.warn("Registry load attempt %d/%d failed: %s", attempt, MaxRetries, tostring(data))
				task.wait(RetryDelay)
			end
		end
	end
 
	local subOk, connection = pcall(function()
		return MS:SubscribeAsync(Topic, onMessage)
	end)
 
	if subOk then
		_subscribed = true
		_trove:Add(connection)
	else
		Log.warn("MessagingService subscription failed, falling back to DataStore polling only: %s", tostring(connection))
	end
 
	startFlushLoop()
	startFallbackPoll()
 
	Log.info("OwlFlag bootstrapped. (MessagingService: %s)", _subscribed and "connected" or "unavailable")
end

-- > // Func : Create Flag \\ < --

function OwlFlag.CreateFlag(name: string, config: FlagConfig?): FlagState
	assert(IsServer, "[Owl - Flags] CreateFlag can only be called on the server.")
	assert(type(name) == "string" and #name > 0, "[Owl - Flags] Flag name must be a non empty string.")
	assert(not _flags[name], ("[Owl - Flags] Flag %q already exists, use SetFlag() to edit it."):format(name))
 
	local state = defaultState(name, config)
	_flags[name] = state
	_dirty[name] = true
 
	persistRegistry()
	publishFlag(name, state)
	OwlFlag.Changed:Fire(name, state)
 
	Log.info("Flag %q created (Scope=%s, Rollout=%d%%).", name, state.Scope, state.RolloutPercent)
	return state
end

-- > // Func : Set Flag \\ < --

function OwlFlag.SetFlag(name: string, config: FlagConfig): FlagState
	assert(IsServer, "[Owl - Flags] SetFlag can only be called on the server.")
	assert(type(name) == "string" and #name > 0, "[Owl - Flags] Flag name must be a non empty string.")
 
	local existing = _flags[name]
	if not existing then
		return OwlFlag.CreateFlag(name, config)
	end
 
	local whitelist = existing.Whitelist
	local blacklist = existing.Blacklist
 
	if config.Whitelist then
		whitelist = {}

		for _, id in ipairs(config.Whitelist) do 
            whitelist[id] = true 
        end
	end
 
	if config.Blacklist then
		blacklist = {}

		for _, id in ipairs(config.Blacklist) do 
            blacklist[id] = true 
        end
	end
 
	local newState: FlagState = {
		Name = name,
		Scope = config.Scope or existing.Scope,
		Enabled = if config.Enabled ~= nil then config.Enabled else existing.Enabled,
		RolloutPercent = math.clamp(config.RolloutPercent or existing.RolloutPercent, 0, 100),
		Whitelist = whitelist,
		Blacklist = blacklist,
		UpdatedAt = os.time(),
		Version = existing.Version + 1,
	}
 
	_flags[name] = newState
	_dirty[name] = true
 
	persistRegistry()
	publishFlag(name, newState)
	OwlFlag.Changed:Fire(name, newState)
 
	Log.info("Flag %q updated (v%d).", name, newState.Version)
	return newState
end

-- > // Func : Delete Flag \\ < --

function OwlFlag.DeleteFlag(name: string)
	assert(IsServer, "[Owl - Flags] DeleteFlag can only be called on the server.")
	if not _flags[name] then return end
 
	_flags[name] = nil
	_dirty[name] = nil
 
	persistRegistry()
	publishFlag(name, nil)
	OwlFlag.Changed:Fire(name, nil)
 
	Log.info("Flag %q deleted.", name)
end

-- > // Func : Get Flag \\ < --

function OwlFlag.GetFlag(name: string): FlagState?
	return _flags[name]
end

-- > // Func : Get All \\ < --

function OwlFlag.GetAll(): {[string]: FlagState}
	local copy = {}

	for name, state in pairs(_flags) do
		copy[name] = state
	end

	return copy
end

-- > // Func : Get Bucket \\ < --
-- > // just a debug thing
function OwlFlag.GetBucket(name: string, userId: number): number
	return stableHash(name, userId)
end

-- > // Func : Is Enabled \\ < --

function OwlFlag.IsEnabled(name: string, plr: Player): boolean
	local state = _flags[name]
 
	if not state then
		Log.warn("IsEnabled checked on unknown flag %q, defaulting to false.", name)
		return false
	end
 
	local userId = plr.UserId
 
	if state.Blacklist[userId] then
		return false
	end
 
	if state.Whitelist[userId] then
		return true
	end
 
	if not state.Enabled then
		return false
	end
 
	if state.RolloutPercent >= 100 then return true end
	if state.RolloutPercent <= 0 then return false end
 
	return stableHash(name, userId) < state.RolloutPercent
end

-- > // Func : Destroy \\ < --

function OwlFlag.Destroy()
	_trove:Destroy()
	_trove = Trove.new()
 
	table.clear(_flags)
	table.clear(_dirty)
	table.clear(_lastPublish)
 
	_store = nil
	_subscribed = false
	_bootstrapped = false
end
 
return OwlFlag