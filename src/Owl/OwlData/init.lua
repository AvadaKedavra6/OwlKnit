--[[
				Owl - Data
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "[Owl - Data] Can only be used on the server.")

--

local Promise = require(script.Parent.Parent.Libs.Promise)
local Signal = require(script.Parent.Parent.Libs.Signal)
local Trove = require(script.Parent.Parent.Libs.Trove)

--

local OwlShared = require(script.Parent.OwlShared)
local OwlProfile = require(script.OwlProfile)
local Log = OwlShared.Logger("Data")

--

local OwlData = {}
local _owl: any = nil
local _adapter: any = nil
local _profiles: {[number]: any} = {}
local _pending: {[number]: any} = {}
local _trove = Trove.new()
local _started = false

--

OwlData.ProfileLoaded = Signal.new()
OwlData.ProfileReleased = Signal.new()
OwlData.SaveFailed = Signal.new()

--

local DefaultConfig = {
	Backend = "ProfileStore",
	AutoSave = true,
	SaveInterval = 60,
}

-- > // Func : Resolve Adapter \\ < --

local function resolveAdapter(config: {[string]: any})
	local backend = config.Backend or DefaultConfig.Backend
	
	if backend == "ProfileStore" then
		local ok, Adapter = pcall(require, script.ProfileStoreAdapter)
		
		if ok then
			Log.info("Using ProfileStore backend.")
			return Adapter
		else
			Log.warn("ProfileStore backend failed to load: %s, falling back to DataStore2.", tostring(Adapter))
			backend = "DataStore2"
		end
	end
	
	if backend == "DataStore2" then
		local ok, Adapter = pcall(require, script.DataStoreAdapter)
		
		if ok then
			Log.info("Using DataStore2 backend.")
			return Adapter
		else
			Log.warn("DataStore2 backend failed to load: %s", tostring(Adapter))
		end
	end
	
	error("[Owl - Data] No valid backend available. Check your Packages/Libs folder.")
end

-- > // Func : Release Profile \\ < --

local function releaseProfile(plr: Player)
	local profile = _profiles[plr.UserId]
	if not profile then return end
	
	_profiles[plr.UserId] = nil
	profile:_release()
	
	Log.info("Profile released for %s.", plr.Name)
	OwlData.ProfileReleased:Fire(plr)
end

-- > // Func : Fire Profile Loaded \\ < --

local function fireProfileLoaded(plr: Player, profile: any)
	if not _owl then return end
	local registry = _owl._GetServiceRegistry and _owl._GetServiceRegistry() or {}
	
	for _, service in pairs(registry) do
		if type(service.OwlOnProfileLoaded) == "function" then
			task.spawn(function()
				local ok, err = pcall(service.OwlOnProfileLoaded, service, plr, profile)
				
				if not ok then
					Log.warn("Error in OwlOnProfileLoaded for service %q: %s", tostring(service.Name), tostring(err))
				end
			end)
		end
	end
end

-- > // Func : Bootstrap \\ < --

function OwlData._Bootstrap(owl: any)
	assert(not _started, "[Owl - Data] OwlData already bootstrapped.")
	_owl = owl
	_started = true
	
	local config = (owl.Config and owl.Config.Data) or DefaultConfig
	local AdapterClass = resolveAdapter(config)
	OwlData._AdapterClass = AdapterClass
	
	if config.AutoSave ~= false then
		local interval = config.SaveInterval or DefaultConfig.SaveInterval
		local accumulated = 0

		_trove:Add(RunService.Heartbeat:Connect(function(dt)
			accumulated += dt
			
			if accumulated >= interval then
				accumulated = 0
				OwlData._AutoSave()
			end
		end))

		Log.info("Auto-save enabled every %ds.", interval)
	end
	
	game:BindToClose(function()
		Log.info("Server closing, saving all profiles...")
		OwlData.SaveAll()
	end)

	Log.info("OwlData bootstrapped with backend %q.", config.Backend or DefaultConfig.Backend)
end

-- > // Func : Load Profile \\ < --

function OwlData.Load(plr: Player, opts: {storeName: string, schema: {[string]: any}, migrations: {[number]: (data: {[string]: any}) -> ()}?}): any
	assert(type(opts.storeName) == "string" and #opts.storeName > 0, "[Owl - Data] Load: storeName must be a non empty string.")
	assert(type(opts.schema) == "table", "[Owl - Data] Load: schema must be a table.")
	
	if not _started then
		return Promise.new(function(resolve, reject)
			local attempts = 0
			repeat
				task.wait(0.1)
				attempts += 1
			until _started or attempts >= 50

			if not _started then
				reject("[Owl - Data] Load: OwlData not bootstrapped after 5s. Make sure Owl.Start() has been called.")
				return
			end

			OwlData.Load(plr, opts):andThen(resolve):catch(reject)
		end)
	end

	if _profiles[plr.UserId] then
		Log.warn("Profile for %s is already loaded.", plr.Name)
		return Promise.resolve(_profiles[plr.UserId])
	end
	
	if _pending[plr.UserId] then
		return _pending[plr.UserId]
	end
	
	local adapter = OwlData._AdapterClass.new(opts.storeName, opts.schema, opts.migrations)
	
	local loadPromise = adapter:Load(plr):andThen(function(result)
		if plr.Parent == nil then
			pcall(result.onRelease)
			return Promise.reject("Player left before profile was ready.")
		end
		
		local profile = OwlProfile.new(plr, result.data, result.onSave, result.onRelease)
		
		profile.SaveFailed:Connect(function(err)
			OwlData.SaveFailed:Fire(plr, err)
		end)
		
		_profiles[plr.UserId] = profile
		_pending[plr.UserId] = nil
		
		Log.info("Profile ready for %s.", plr.Name)
		OwlData.ProfileLoaded:Fire(plr, profile)
		
		fireProfileLoaded(plr, profile)
		return profile
	end):catch(function(err)
		_pending[plr.UserId] = nil
		Log.warn("Failed to load profile for %s: %s", plr.Name, tostring(err))
		OwlData.SaveFailed:Fire(plr, err)
		return Promise.reject(err)
	end)
	
	_pending[plr.UserId] = loadPromise
	return loadPromise
end

-- > // Func : Get Profile \\ < --

function OwlData.Get(plr: Player): any?
	return _profiles[plr.UserId]
end

-- > // Func : Await Profile \\ < --

function OwlData.Await(plr: Player, timeout: number?): any
	local existing = _profiles[plr.UserId]
	if existing then return Promise.resolve(existing) end
	
	if _pending[plr.UserId] then 
		return _pending[plr.UserId]
	end
	
	return Promise.new(function(resolve, reject)
		local conn: RBXScriptConnection
		local timeoutThread: thread?

		conn = OwlData.ProfileLoaded:Connect(function(loadedPlr, profile)
			if loadedPlr == plr then
				if timeoutThread then task.cancel(timeoutThread) end
				conn:Disconnect()
				resolve(profile)
			end
		end)

		if timeout then
			timeoutThread = task.delay(timeout, function()
				conn:Disconnect()
				reject(("[Owl - Data] Await timeout (%ds) for %s."):format(timeout, plr.Name))
			end)
		end
	end)
end

-- > // Func : Release Plr \\ < --

function OwlData._ReleasePlayer(plr: Player)
	releaseProfile(plr)
end

-- > // Func : Save All \\ < --

function OwlData.SaveAll()
	local count = 0
	
	for userId, profile in pairs(_profiles) do
		local ok, err = pcall(function()
			profile:Save()
		end)
		
		if not ok then
			Log.warn("SaveAll: failed for userId %d: %s", userId, tostring(err))
		else
			count += 1
		end
	end
	
	Log.info("SaveAll: %d profile(s) saved.", count)
end

-- > // Func : Auto Save \\ < --

function OwlData._AutoSave()
	for _, profile in pairs(_profiles) do
		if not profile:IsReleased() then
			profile:Save():catch(function(err)
				Log.warn("AutoSave failed for %s: %s", profile._plr.Name, tostring(err))
			end)
		end
	end
end

-- > // Func : Destroy \\ < --

function OwlData._Destroy()
	OwlData.SaveAll()
	_trove:Destroy()
	
	table.clear(_profiles)
	table.clear(_pending)
	
	_started = false
	_owl     = nil
	_adapter = nil
end

return OwlData