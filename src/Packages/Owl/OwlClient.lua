--[[
				Owl - Client
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
assert(RunService:IsClient(), "[Owl] OwlClient can only be used in client.")

--

local Comm = require(RepStorage.Packages.Libs.Comm)
local Trove = require(RepStorage.Packages.Libs.Trove)
local Signal = require(RepStorage.Packages.Libs.Signal)
local Promise = require(RepStorage.Packages.Libs.Promise)
local ClientComm = Comm.ClientComm

--

local OwlShared = require(script.Parent.OwlShared)
local OwlComponent = require(script.Parent.OwlComponent)
local Log = OwlShared.Logger("Client")

--

local CommParent = RepStorage.Packages
local CommFolderTimeout = 10
local PlayerGuiTimeout = 10

--

local OwlClient = {}
local _owl: any = nil
local _clientComms: {[string]: any} = {}
local _commFolder: Instance? = nil

-- > // Types \\ < --

type Middleware = {(plr: Player, args: {any}) -> (boolean, ...any)}

-- > // Func : Wait For Comm Folder \\ < --

local function waitForCommFolder(parent: Instance, name: string, timeout: number)
	return Promise.new(function(resolve, reject)
		local existing = parent:FindFirstChild(name)
		if existing then resolve(existing) return end

		local conn: RBXScriptConnection
		local timeoutThread: thread

		conn = parent.ChildAdded:Connect(function(child)
			if child.Name == name then
				task.cancel(timeoutThread)
				conn:Disconnect()
				resolve(child)
			end
		end)

		timeoutThread = task.delay(timeout, function()
			conn:Disconnect()
			reject(("[Owl - Client] Timeout waiting for comm folder '%s'. Is OwlServer running ?"):format(name))
		end)
	end)
end

-- > // Func : Wait For Character \\ < --

local function waitForCharacterReady(char: Model)
	local humanoid = char:WaitForChild("Humanoid")
	local rootPart = char:WaitForChild("HumanoidRootPart")
	return humanoid, rootPart
end

-- > // Func : Get Or Create Svc Proxy \\ < --

local function getOrCreateServiceProxy(serviceFolder: Instance, serviceName: string)
	if _clientComms[serviceName] then
		return _clientComms[serviceName]._proxy
	end

	local clientComm = ClientComm.new(_commFolder, true, serviceName)
	
	local rfFolder = serviceFolder:FindFirstChild("Owl_RF")
	local reFolder = serviceFolder:FindFirstChild("Owl_RE")
	local rpFolder = serviceFolder:FindFirstChild("Owl_RP")

	local resolved: {[string]: any} = {}

	local proxy = setmetatable({}, {
		__index = function(_, key: string)
			if resolved[key] then
				return resolved[key]
			end

			local hashed = OwlShared.HashName(key)
			local remote: any = nil

			if rfFolder and rfFolder:FindFirstChild(hashed) then
				remote = clientComm:GetFunction(hashed)
			elseif reFolder and reFolder:FindFirstChild(hashed) then
				remote = clientComm:GetSignal(hashed)
			elseif rpFolder and rpFolder:FindFirstChild(hashed) then
				remote = clientComm:GetProperty(hashed)
			else
				Log.warn("Remote %q (hash: %s) not found in service %q.", key, hashed, serviceName)
				return nil
			end

			resolved[key] = remote
			return remote
		end,

		__newindex = function()
			error("[Owl] Service proxy is read-only.", 2)
		end,
	})

	_clientComms[serviceName] = {
		_comm  = clientComm,
		_proxy = proxy,
	}

	return proxy
end

-- > // Func : Auto Watch Client Components \\ < --

local function autoWatchClientComponents()
	local registry = OwlComponent._GetRegistry and OwlComponent._GetRegistry() or {}

	for _, comp in pairs(registry) do
		if comp._type == "Client" and not comp._started then
			local ok, err = pcall(function()
				comp:Watch()
			end)

			if not ok then
				Log.warn("Failed to auto-watch component %q: %s", tostring(comp._tag), tostring(err))
			else
				Log.info("Auto-watching Client component %q.", comp._tag)
			end
		end
	end
end

-- > // Func : BootStrap COntroller \\ < --

local function bootstrapController(controller: any)
	local controllerName = controller.Name :: string
	local trove = Trove.new()
	local plr = Players.LocalPlayer
	
	controller._trove = trove
	controller.Trove = trove
	
	controller.GetController = function(_self: any, name: string)
		return _owl.GetController(name)
	end
	
	controller.GetService = function(_self: any, name: string)
		return _owl.GetService(name)
	end
	
	controller.CreateLocalSignal = function(_self: any)
		local sig = Signal.new()
		trove:Add(sig)
		return sig
	end
	
	if type(controller.OwlOnCharacterAdded) == "function" then
		if plr.Character then
			task.spawn(function()
				controller:OwlOnCharacterAdded(plr.Character)
			end)
		end

		trove:Add(plr.CharacterAdded:Connect(function(char: Model)
			controller:OwlOnCharacterAdded(char)
		end))
	end
	
	if type(controller.OwlOnCharacterRemoving) == "function" then
		if plr.Character then
			local charTrove = Trove.new()
			trove:Add(charTrove)

			charTrove:Add(plr.CharacterRemoving:Connect(function(char: Model)
				controller:OwlOnCharacterRemoving(char)
				charTrove:Destroy()
			end))
		end

		trove:Add(plr.CharacterAdded:Connect(function(char: Model)
			local charTrove = Trove.new()
			trove:Add(charTrove)

			charTrove:Add(plr.CharacterRemoving:Connect(function(removingChar: Model)
				controller:OwlOnCharacterRemoving(removingChar)
				charTrove:Destroy()
			end))
		end))
	end
	
	if type(controller.OwlOnPlayerCharacterReady) == "function" then
		local function handleCharacter(plr: Player, char: Model)
			task.spawn(function()
				waitForCharacterReady(char)
				controller:OwlOnPlayerCharacterReady(plr, char)
			end)
		end

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				handleCharacter(plr, plr.Character)
			end

			trove:Add(plr.CharacterAdded:Connect(function(char: Model)
				handleCharacter(plr, char)
			end))
		end

		trove:Add(Players.PlayerAdded:Connect(function(plr: Player)
			trove:Add(plr.CharacterAdded:Connect(function(char: Model)
				handleCharacter(plr, char)
			end))
		end))
	end
	
	if type(controller.OwlOnLocalPlayerReady) == "function" then
		task.spawn(function()
			local playerGui = plr:FindFirstChild("PlayerGui")

			if not playerGui then
				local waiting = true

				task.delay(PlayerGuiTimeout, function()
					if waiting then
						Log.warn(
							"Controller %q: OwlOnLocalPlayerReady is waiting for PlayerGui for over %ds. " ..
								"Is StarterGui loaded correctly ?",
							controllerName,
							PlayerGuiTimeout
						)
					end
				end)

				playerGui = plr:WaitForChild("PlayerGui")
				waiting   = false
			end

			controller:OwlOnLocalPlayerReady(plr)
		end)
	end

	if type(controller.OwlOnPlayerLeft) == "function" then
		trove:Add(Players.PlayerRemoving:Connect(function(plr: Player)
			controller:OwlOnPlayerLeft(plr)
		end))
	end
	
	controller.Destroy = function(self: any)
		if type(self.OwlDestroy) == "function" then
			pcall(self.OwlDestroy, self)
		end

		self._trove:Destroy()
	end

	Log.info("Bootstrapped controller %q.", controllerName)
end

-- > // Func : Bootstrap \\ < --

function OwlClient.Bootstrap(owl: any)
	_owl = owl
	local registry = owl._GetControllerRegistry()

	for _, controller in pairs(registry) do
		bootstrapController(controller)
	end

	local count = 0
	for _ in pairs(registry) do count += 1 end
	Log.info("Bootstrapped %d controller(s).", count)

	return waitForCommFolder(CommParent, "Comm", CommFolderTimeout):andThen(function(commFolder)
		_commFolder = commFolder
		local serviceCount = 0

		for _, serviceFolder in ipairs(commFolder:GetChildren()) do
			if serviceFolder:IsA("Folder") then
				local serviceName = serviceFolder.Name
				local proxy = getOrCreateServiceProxy(serviceFolder, serviceName)

				owl._InjectClientServiceProxy(serviceName, proxy)
				serviceCount += 1

				Log.info("Service proxy created: %q.", serviceName)
			end
		end

		commFolder.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Folder") then
				local serviceName = child.Name

				if not _clientComms[serviceName] then
					local proxy = getOrCreateServiceProxy(child, serviceName)
					owl._InjectClientServiceProxy(serviceName, proxy)
					Log.info("Late service proxy created: %q.", serviceName)
				end
			end
		end)

		task.defer(autoWatchClientComponents)
		print(("[Owl - Client] %d service proxy(ies) ready."):format(serviceCount))
	end)
end

-- > // Func : Destroy \\ < --

function OwlClient.Destroy()
	for _, entry in pairs(_clientComms) do
		entry._comm:Destroy()
	end

	table.clear(_clientComms)
	_commFolder = nil
end

return OwlClient