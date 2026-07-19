--[[
				Owl - Server
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local StarterPack = game:GetService("StarterPack")
assert(RunService:IsServer(), "[Owl] OwlServer can only be used in server.")

--

local Comm = require(RepStorage.OwlKnit.Libs.Comm)
local Signal = require(RepStorage.OwlKnit.Libs.Signal)
local Trove = require(RepStorage.OwlKnit.Libs.Trove)
local Promise = require(RepStorage.OwlKnit.Libs.Promise)
local ServerComm = Comm.ServerComm

--

local OwlShared = require(script.Parent.OwlShared)
local OwlComponent = require(script.Parent.OwlComponent)
local Log = OwlShared.Logger("Server")

--

local CommParent = RepStorage.OwlKnit
local OwlServer = {}
local _owl: any = nil
local _manualSpawn = false
local _spawnDebounce: {[Player]: boolean} = {}

-- > // Types \\ < --

type Middleware = {(plr: Player, args: {any}) -> (boolean, ...any)}

-- > // Func : Merge Middleware \\ < --

local function mergeMiddleware(global: Middleware, service: Middleware, remote: Middleware): Middleware
	local merged: Middleware = {}
	
	for _, fn in ipairs(global) do
		table.insert(merged, fn)
	end
	
	for _, fn in ipairs(service) do
		table.insert(merged, fn)
	end
	
	for _, fn in ipairs(remote) do
		table.insert(merged, fn)
	end
	
	return merged
end

-- > // Funbc : Replicate Content \\ < --

local function replicateStarterContent(plr: Player)
	local plrGui = plr:FindFirstChildOfClass("PlayerGui")
	local backpack = plr:FindFirstChildOfClass("Backpack")

	if plrGui then
		for _, item in ipairs(StarterGui:GetChildren()) do
			if not plrGui:FindFirstChild(item.Name) then
				local clone = item:Clone()
				clone.Parent = plrGui
			end
		end
	else
		Log.warn("SpawnPlr: PlayerGui not found for %q, StarterGui not replicated.", plr.Name)
	end

	if backpack then
		for _, item in ipairs(StarterPack:GetChildren()) do
			if not backpack:FindFirstChild(item.Name) then
				local clone = item:Clone()
				clone.Parent = backpack
			end
		end
	else
		Log.warn("SpawnPlr: Backpack not found for %q, StarterPack not replicated.", plr.Name)
	end
end

-- > // Func : Spawn Player \\ < --

function OwlServer.SpawnPlr(plr: Player)
	assert(typeof(plr) == "Instance" and plr:IsA("Player"), "[Owl] SpawnPlr expects a Player instance.")

	if _spawnDebounce[plr] then
		Log.warn("SpawnPlr: call ignored for %q, a spawn is already in progress.", plr.Name)
		return
	end

	_spawnDebounce[plr] = true
	plr:LoadCharacterAsync()

	if _manualSpawn then
		task.defer(function()
			if plr.Parent then
				replicateStarterContent(plr)
			end
			
			_spawnDebounce[plr] = nil
		end)
	else
		_spawnDebounce[plr] = nil
	end
end

-- > // Func : Watch Server \\ < --

local function autoWatchServerComponents()
	local registry = OwlComponent._GetRegistry()
	
	for comp in pairs(registry) do
		if comp._type == "Server" and not comp._started then
			local ok, err = pcall(function()
				comp:Watch()
			end)
			
			if not ok then
				Log.warn("Failed to auto watch component %q: %s", tostring(comp._tag), tostring(err))
			else
				Log.info("Auto watching server component %q.", comp._tag)
			end
		end
	end
end

-- > // Func : BootStrap Serrcie \\ < --

local function bootstrapService(service: any, globalMiddleware: {Inbound: Middleware, Outbound: Middleware})
	local serviceName = service.Name :: string
	local trove = Trove.new()
	
	local commFolder = CommParent:FindFirstChild("Comm")
	if not commFolder then
		commFolder = Instance.new("Folder")
		commFolder.Name = "Comm"
		commFolder.Parent = CommParent
	end

	local comm = ServerComm.new(commFolder, serviceName)
	trove:Add(comm)
	
	service._comm = comm
	service._trove = trove
	service.Trove = trove
	
	local svcInbound: Middleware = (service.Middleware and service.Middleware.Inbound) or {}
	local svcOutbound: Middleware = (service.Middleware and service.Middleware.Outbound) or {}
	
	local clientTable = service.Client
	if type(clientTable) ~= "table" then
		service.Client = {}
		return
	end
	
	for key, value in pairs(clientTable) do
		local hashedKey = OwlShared.HashName(key)
		
		if type(value) == "function" then
			local inboundMw = mergeMiddleware(globalMiddleware.Inbound, svcInbound, {})
			local outboundMw = mergeMiddleware(globalMiddleware.Outbound, svcOutbound, {})
			
			comm:BindFunction(hashedKey, function(plr: Player, ...)
				if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
					return nil
				end
				
				local ok, result = pcall(value, service, plr, ...)
				
				if not ok then
					Log.warn("Remote error in service %q, key%q: %s", serviceName, key, tostring(result))
					return nil
				end
				
				return result
			end,
				#inboundMw > 0 and inboundMw or nil,
				#outboundMw > 0 and outboundMw or nil
			)
			
			Log.info("Service %q bound client function %q.", serviceName, key)
			
		elseif type(value) == "table" then
			local marker = value :: any
			
			if marker._owlType == "Signal" then
				local inboundMw = mergeMiddleware(globalMiddleware.Inbound, svcInbound, marker._inbound)
				local outboundMw = mergeMiddleware(globalMiddleware.Outbound, svcOutbound, marker._outbound)
				local remoteSignal = comm:CreateSignal(hashedKey, marker._unreliable, #inboundMw  > 0 and inboundMw  or nil, #outboundMw > 0 and outboundMw or nil)

				clientTable[key] = remoteSignal
				trove:Add(remoteSignal)
				
				Log.info("Service %q created client signal %q.", serviceName, key)
			
			elseif marker._owlType == "Property" then
				local inboundMw = mergeMiddleware(globalMiddleware.Inbound, svcInbound, marker._inbound)
				local outboundMw = mergeMiddleware(globalMiddleware.Outbound, svcOutbound, marker._outbound)
				local remoteProperty = comm:CreateProperty(hashedKey, marker._initial, #inboundMw  > 0 and inboundMw  or nil, #outboundMw > 0 and outboundMw or nil)

				clientTable[key] = remoteProperty
				trove:Add(remoteProperty)

				Log.info("Service %q created client property %q.", serviceName, key)
			else
				Log.warn("Service %q: client value %q is not a function or marker, ignored.", serviceName, key)
			end
		end
	end
	
	--
	
	service.GetService = function(_self: any, name: string)
		return _owl.GetService(name)
	end
	
	service.CreateLocalSignal = function(_self: any)
		local sig = Signal.new()
		trove:Add(sig)
		return sig
	end
	
	service.Destroy = function(self: any)
		if type(self.OwlDestroy) == "function" then
			pcall(self.OwlDestroy, self)
		end
		
		self._trove:Destroy()
	end
	
	--
	
	if type(service.OwlOnPlayerAdded) == "function" then
		for _, plr in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				service:OwlOnPlayerAdded(plr)
			end)
		end

		trove:Add(Players.PlayerAdded:Connect(function(plr: Player)
			service:OwlOnPlayerAdded(plr)
		end))
	end
	
	if type(service.OwlOnPlayerRemoving) == "function" then
		trove:Add(Players.PlayerRemoving:Connect(function(plr: Player)
			service:OwlOnPlayerRemoving(plr)
			_spawnDebounce[plr] = nil
		end))
	end
	
	if type(service.OwlOnCharacterAdded) == "function" or type(service.OwlOnCharacterRemoving) == "function" then
		local playerTroves: {[number]: any} = {}

		local function setupCharacterLifecycle(plr: Player)
			if playerTroves[plr.UserId] then
				playerTroves[plr.UserId]:Destroy()
				playerTroves[plr.UserId] = nil
			end

			local plrTrove = Trove.new()
			playerTroves[plr.UserId] = plrTrove

			if plr.Character and type(service.OwlOnCharacterAdded) == "function" then
				task.spawn(function()
					service:OwlOnCharacterAdded(plr, plr.Character)
				end)
			end

			if type(service.OwlOnCharacterAdded) == "function" then
				plrTrove:Add(plr.CharacterAdded:Connect(function(char: Model)
					service:OwlOnCharacterAdded(plr, char)
				end))
			end

			if type(service.OwlOnCharacterRemoving) == "function" then
				plrTrove:Add(plr.CharacterRemoving:Connect(function(char: Model)
					service:OwlOnCharacterRemoving(plr, char)
				end))
			end
		end

		for _, plr in ipairs(Players:GetPlayers()) do
			setupCharacterLifecycle(plr)
		end

		trove:Add(Players.PlayerAdded:Connect(function(plr: Player)
			setupCharacterLifecycle(plr)
		end))

		trove:Add(Players.PlayerRemoving:Connect(function(plr: Player)
			if playerTroves[plr.UserId] then
				playerTroves[plr.UserId]:Destroy()
				playerTroves[plr.UserId] = nil
			end
			
			_spawnDebounce[plr] = nil
		end))
	end
	
	if type(service.OwlOnSpawnReady) == "function" then
		if not _manualSpawn then
			Log.warn("Service %q defines OwlOnSpawnReady but CharacterAutoLoads is enabled. " .. "This hook only fires when using Owl.SpawnPlr().",serviceName)
		end

		trove:Add(Players.PlayerAdded:Connect(function(plr: Player)
			plr.CharacterAdded:Connect(function(char: Model)
				task.spawn(function()
					service:OwlOnSpawnReady(plr, char)
				end)
			end)
		end))

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				task.spawn(function()
					service:OwlOnSpawnReady(plr, plr.Character)
				end)
			end

			trove:Add(plr.CharacterAdded:Connect(function(char: Model)
				task.spawn(function()
					service:OwlOnSpawnReady(plr, char)
				end)
			end))
		end
	end

	Log.info("Service %q bootstrapped.", serviceName)
end

-- > // Func : Start \\ < --

function OwlServer.Bootstrap(owl: any, globalMiddleware: {Inbound: Middleware?, Outbound: Middleware?}?)
	_owl = owl
	_manualSpawn = not Players.CharacterAutoLoads
	
	if _manualSpawn then
		Log.warn("CharacterAutoLoads is disabled. " .. "Use Owl.SpawnPlr(plr) to load characters and replicate StarterGui/StarterPack.")
	end
	
	local configMw = owl.Config and owl.Config.GlobalMiddleware
	local resolvedMw: {Inbound: Middleware, Outbound: Middleware} = {
		Inbound  = (globalMiddleware and globalMiddleware.Inbound)
			or (configMw and configMw.Inbound)
			or {},
		Outbound = (globalMiddleware and globalMiddleware.Outbound)
			or (configMw and configMw.Outbound)
			or {},
	}
	
	local registry = owl._GetServiceRegistry and owl._GetServiceRegistry()
	local count = 0
	
	for _, service in pairs(registry) do
		bootstrapService(service, resolvedMw)
		count += 1
	end
	
	local owlDataOk, OwlData = pcall(require, script.Parent.OwlData)
	if owlDataOk and type(OwlData._Bootstrap) == "function" then
		OwlData._Bootstrap(owl)
	else
		Log.warn("OwlData not found or failed to load, data features unavailable. (%s)", tostring(OwlData))
	end
	
	task.defer(autoWatchServerComponents)
	Log.info("Bootstrapped %d services.", count)
end

-- > // Func : Destroy \\ < --

function OwlServer.Destroy()
	_manualSpawn = false
	_owl = nil
end

return OwlServer