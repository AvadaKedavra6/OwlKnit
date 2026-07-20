--[[
				Owl - Main
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

--

local Promise = require(script.Parent.Libs.Promise)
local Signal = require(script.Parent.Libs.Signal)
local Trove = require(script.Parent.Libs.Trove)
local Timer = require(script.Parent.Libs.Timer)

local OwlShared = require(script.OwlShared)
local Log = OwlShared.Logger("Owl")

-- > // Types \\ < --

export type MiddlewareFn = (plr: Player, args: {any}) -> (boolean, ...unknown)
export type Middleware = {MiddlewareFn}

--

export type GlobalMiddleware = {
	Inbound: Middleware?,
	Outbound: Middleware?,
}

--

export type DataConfig = {
	Backend: "ProfileStore" | "DataStore2",
	AutoSave: boolean?,
	SaveInterval: number?,
}

--

export type StartConfig = {
	Verbose: boolean?,
	InitTimeout: number?,
	StartTimeout: number?,
	GlobalMiddleware: GlobalMiddleware?,
	Data: DataConfig?,
}

--

export type ServiceConfig = {
	Name: string,
	Dependencies: {string}?,
	Middleware: {Inbound: Middleware?, Outbound: Middleware?}?,
	Client: {[string]: unknown}?,
	OwlInit: ((self: RegisteredService) -> ())?,
	OwlStart: ((self: RegisteredService) -> ())?,
	OwlDestroy: ((self: RegisteredService) -> ())?,
	OwlOnPlayerAdded: ((self: RegisteredService, plr: Player) -> ())?,
	OwlOnPlayerRemoving: ((self: RegisteredService, plr: Player) -> ())?,
	OwlOnCharacterAdded: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	OwlOnCharacterRemoving: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	OwlOnSpawnReady: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	[string]: unknown,
}

--

export type ControllerConfig = {
	Name: string,
	Dependencies: {string}?,
	OwlInit: ((self: RegisteredController) -> ())?,
	OwlStart: ((self: RegisteredController) -> ())?,
	[string]: unknown,
}

--

type TroveLike = {Destroy: (self: TroveLike) -> ()}
type CommLike = {Destroy: (self: CommLike) -> ()}
export type ServiceProxy = {[string]: unknown}

--

type RegisteredService = {
	Name: string,
	Dependencies: {string},
	Middleware: {Inbound: Middleware, Outbound: Middleware},
	Client: {[string]: unknown},
	OwlInit: ((self: RegisteredService) -> ())?,
	OwlStart: ((self: RegisteredService) -> ())?,
	OwlDestroy: ((self: RegisteredService) -> ())?,
	OwlOnPlayerAdded: ((self: RegisteredService, plr: Player) -> ())?,
	OwlOnPlayerRemoving: ((self: RegisteredService, plr: Player) -> ())?,
	OwlOnCharacterAdded: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	OwlOnCharacterRemoving: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	OwlOnSpawnReady: ((self: RegisteredService, plr: Player, char: Model) -> ())?,
	_comm: CommLike?,
	_trove: TroveLike?,
	[string]: unknown,
}

--

type RegisteredController = {
	Name: string,
	Dependencies: {string},
	OwlInit: ((self: RegisteredController) -> ())?,
	OwlStart: ((self: RegisteredController) -> ())?,
	[string]: unknown,
}

--

type LifecycleItem = {
	Name: string,
	Dependencies: {string},
	OwlInit: ((self: LifecycleItem) -> ())?,
	OwlStart: ((self: LifecycleItem) -> ())?,
}

-- > // Others Variables \\ < --

local _started = false
local _starting = false
local _services: {[string]: RegisteredService} = {}
local _controllers: {[string]: RegisteredController} = {}
local _tokens: {[Player]: string} = {}

--

local _onPlayerAddedListeners: {RegisteredService} = {}
local _onPlayerRemovingListeners: {RegisteredService} = {}
local _onCharacterAddedListeners: {RegisteredService} = {}
local _onCharacterRemovingListeners: {RegisteredService} = {}
local _onStartSignal = Signal.new()

--

local Owl = {}

Owl.Config = {
	Verbose = false,
	InitTimeout = 30,
	StartTimeout = 30,
	GlobalMiddleware = {
		Inbound = {},
		Outbound = {},
	},
	Data = {
		Backend = "ProfileStore",
		AutoSave = true,
		SaveInterval = 60,
	}
} :: StartConfig

Owl.Util = {
	Signal = Signal,
	Promise = Promise,
	Trove = Trove,
	Timer = Timer,
	TypeChecker = require(script.Parent.Middleware.TypeChecker),
	RateLimiter = require(script.Parent.Middleware.RateLimiter),
	Component = require(script.OwlComponent),
	Data = IsServer and require(script.OwlData) or nil,
	Action = IsClient and require(script.OwlAction) or nil,
	Logger = OwlShared.Logger,
}

-- > // Func : Create Service \\ < --

function Owl.CreateService(config: ServiceConfig): RegisteredService
	assert(IsServer, "[Owl] CreateService can only be called on the server.")
	assert(type(config.Name) == "string" and #config.Name > 0, "[Owl] Service must have a non empty name.")
	assert(not _started and not _starting, ("[Owl] Cannot create service %q after Owl.Start() has been called."):format(config.Name))
	assert(not _services[config.Name], ("[Owl] A service named %q is already registered."):format(config.Name))
	
	local service: RegisteredService = {
		Name = config.Name,
		Dependencies = config.Dependencies or {},
		Middleware = {
			Inbound = (config.Middleware and config.Middleware.Inbound) or {},
			Outbound = (config.Middleware and config.Middleware.Outbound) or {},
		},
		Client = config.Client or {},
		OwlInit = config.OwlInit,
		OwlStart = config.OwlStart,
		_comm = nil,
	}
	
	for k, v in pairs(config) do
		if service[k] == nil then
			service[k] = v
		end
	end
	
	_services[config.Name] = service
	Log.info("Service %q registered.", config.Name)
	
	return service
end

-- > // Func : Create Controller \\ < --

function Owl.CreateController(config: ControllerConfig): RegisteredController
	assert(IsClient, "[Owl] CreateController can only be called on the client.")
	assert(type(config.Name) == "string" and #config.Name > 0, "[Owl] Controller must have a non empty name.")
	assert(not _started and not _starting, ("[Owl] Cannot create controller %q after Owl.Start() has been called."):format(config.Name))
	assert(not _controllers[config.Name], ("[Owl] A controller named %q is already registered."):format(config.Name))
	
	local controller: RegisteredController = {
		Name = config.Name,
		Dependencies = config.Dependencies or {},
		OwlInit = config.OwlInit,
		OwlStart = config.OwlStart,
	}
	
	for k, v in pairs(config) do
		if controller[k] == nil then
			controller[k] = v
		end
	end
	
	_controllers[config.Name] = controller
	Log.info("Controller %q registered.", config.Name)
	
	return controller
end

-- > // Func : Get Service \\ < --

function Owl.GetService(name: string): RegisteredService
	local entry = _services[name]
	assert(entry, ("[Owl] Service %q does not exist."):format(name))
	return entry
end

-- > // Func : Get Controller \\ < --

function Owl.GetController(name: string): RegisteredController
	assert(IsClient, "[Owl] GetController can only be called on the client.")
	local controller = _controllers[name]
	assert(controller, ("[Owl] Controller %q does not exist."):format(name))
	return controller
end

-- > // Func : Create Signal \\ < --

function Owl.CreateSignal(opts: {unreliable: boolean?, inbound: Middleware?, outbound: Middleware?}?)
	return {
		_owlType = "Signal",
		_unreliable = (opts and opts.unreliable) or false,
		_inbound = (opts and opts.inbound) or {},
		_outbound = (opts and opts.outbound) or {},
	}
end

-- > // Func : Create Property \\ < --

function Owl.CreateProperty<T>(initialValue: T, opts: {inbound: Middleware?, outbound: Middleware?}?)
	return {
		_owlType = "Property",
		_initial = initialValue,
		_inbound = (opts and opts.inbound) or {},
		_outbound = (opts and opts.outbound) or {},
	}
end

-- > // Func : Add Services \\ < --

function Owl.AddServices(folder: Folder)
	assert(IsServer, "[Owl] AddServices can only be called on the server.")
	OwlShared.LoadModules(folder, Log)
end

-- > // Func : Add Controllers \\ < --

function Owl.AddControllers(folder: Folder)
	assert(IsClient, "[Owl] AddControllers can only be called on the client.")
	OwlShared.LoadModules(folder, Log)
end

-- > // Func : Spawn Plr \\ < --

function Owl.SpawnPlr(plr: Player)
	assert(IsServer, "[Owl] SpawnPlr can only be called on the server.")
	assert(_started, "[Owl] SpawnPlr can only be called after Owl.Start().")
	
	local OwlServer = require(script.OwlServer)
	OwlServer.SpawnPlr(plr)
end

-- > // Func : Plr Token \\ < --

function Owl.GetPlrToken(plr: Player): string?
	return _tokens[plr]
end

-- > // Func : Build Lifecycle \\ < --

local function buildLifecycleCache()
	table.clear(_onPlayerAddedListeners)
	table.clear(_onPlayerRemovingListeners)
	table.clear(_onCharacterAddedListeners)
	table.clear(_onCharacterRemovingListeners)
	
	for _, service in pairs(_services) do
		if type(service.OwlOnPlayerAdded) == "function" then
			table.insert(_onPlayerAddedListeners, service)
		end
		
		if type(service.OwlOnPlayerRemoving) == "function" then
			table.insert(_onPlayerRemovingListeners, service)
		end
		
		if type(service.OwlOnCharacterAdded) == "function" then
			table.insert(_onCharacterAddedListeners, service)
		end
		
		if type(service.OwlOnCharacterRemoving) == "function" then
			table.insert(_onCharacterRemovingListeners, service)
		end
	end
	
	Log.info("Lifecycle cache built: PlayerAdded:%d | PlayerRemoving:%d | CharAdded:%d | CharRemoving:%d", #_onPlayerAddedListeners, #_onPlayerRemovingListeners, #_onCharacterAddedListeners, #_onCharacterRemovingListeners)
end

-- > // Func : Player Lifecycle \\ < --

function Owl._BindPlayerLifecycle()
	local function fireList(list: {RegisteredService}, method: string, ...: unknown)
		local args = { ... }
		
		for _, service in ipairs(list) do
			task.spawn(function()
				local fn = (service :: any)[method] :: (self: RegisteredService, ...unknown) -> ()
				fn(service, table.unpack(args))
			end)
		end
	end
 
	local function setupCharacter(plr: Player)
		if plr.Character then
			fireList(_onCharacterAddedListeners, "OwlOnCharacterAdded", plr, plr.Character)
		end
 
		plr.CharacterAdded:Connect(function(char: Model)
			fireList(_onCharacterAddedListeners, "OwlOnCharacterAdded", plr, char)
		end)
 
		plr.CharacterRemoving:Connect(function(char: Model)
			fireList(_onCharacterRemovingListeners, "OwlOnCharacterRemoving", plr, char)
		end)
	end
 
	for _, plr in ipairs(Players:GetPlayers()) do
		_tokens[plr] = OwlShared.NewToken()
		fireList(_onPlayerAddedListeners, "OwlOnPlayerAdded", plr)
		setupCharacter(plr)
	end
 
	Players.PlayerAdded:Connect(function(plr: Player)
		_tokens[plr] = OwlShared.NewToken()
		fireList(_onPlayerAddedListeners, "OwlOnPlayerAdded", plr)
		setupCharacter(plr)
	end)
 
	Players.PlayerRemoving:Connect(function(plr: Player)
		fireList(_onPlayerRemovingListeners, "OwlOnPlayerRemoving", plr)
		task.defer(function()
			_tokens[plr] = nil
		end)
	end)
end

-- > // Func : Start \\ < --

function Owl.Start(startConfig: StartConfig?)
	assert(not _started and not _starting, "[Owl] Owl.Start() has already been called.")
	_starting = true
 
	if startConfig then
		if startConfig.Verbose ~= nil then Owl.Config.Verbose = startConfig.Verbose end
		if startConfig.InitTimeout ~= nil then Owl.Config.InitTimeout = startConfig.InitTimeout end
		if startConfig.StartTimeout ~= nil then Owl.Config.StartTimeout = startConfig.StartTimeout end
		if startConfig.GlobalMiddleware ~= nil then Owl.Config.GlobalMiddleware = startConfig.GlobalMiddleware end
	end
 
	OwlShared.InjectConfig(Owl.Config)
 
	return Promise.new(function(resolve, reject)
		local bootstrapPromise: typeof(Promise.resolve())
 
		if IsServer then
			local OwlServer = require(script.OwlServer)
			OwlServer.Bootstrap(Owl, Owl.Config.GlobalMiddleware)
			bootstrapPromise = Promise.resolve()
 
		elseif IsClient then
			local OwlClient = require(script.OwlClient)
			bootstrapPromise = OwlClient.Bootstrap(Owl)
 
		else
			bootstrapPromise = Promise.resolve()
		end
 
		bootstrapPromise:andThen(function()
			local registry
 
			if IsServer then
				registry = (Owl._GetServiceRegistry() :: any) :: {[string]: LifecycleItem}
			else
				registry = (Owl._GetControllerRegistry() :: any) :: {[string]: LifecycleItem}
			end
 
			local sorted, sortErr = OwlShared.TopologicalSort(registry)
			if sortErr then
				reject(sortErr)
				return
			end
 
			local items: {LifecycleItem} = {}
			for _, name in ipairs(sorted) do
				table.insert(items, registry[name])
			end
 
			Log.info("Starting OwlInit phase (%d items)...", #items)
 
			return OwlShared.RunPhase(
				items,
				function(item: any)
					if item.OwlInit then
						item:OwlInit()
					end
				end,
				"OwlInit",
				Owl.Config.InitTimeout,
				"sequential"
 
			):andThen(function()
				Log.info("Starting OwlStart phase (%d items)...", #items)
 
				return OwlShared.RunPhase(
					items,
					function(item: any)
						if item.OwlStart then
							item:OwlStart()
						end
					end,
					"OwlStart",
					Owl.Config.StartTimeout,
					"parallel"
				)
 
			end):andThen(function()
				_started  = true
				_starting = false
				
				table.freeze(Owl.Config)
 
				if IsServer then
					buildLifecycleCache()
					Owl._BindPlayerLifecycle()
				end
 
				Log.info("Framework started successfully.")
				print("[Owl] Framework started successfully.")
 
				_onStartSignal:Fire()
				resolve()
 
			end):catch(function(err)
				_starting = false
				reject(err)
			end)
 
		end):catch(function(err)
			_starting = false
			reject(err)
		end)
	end)
end

-- > // Func : On Start \\ < --

function Owl.OnStart()
	if _started then
		return Promise.resolve()
	end
	
	return Promise.fromEvent(_onStartSignal)
end

-- > // Func : Is Started \\ < --

function Owl.IsStarted(): boolean
	return _started
end

-- > // Func : Destroy \\ < --

function Owl.Destroy()
	if not _started then return end
	
	for _, service in pairs(_services) do
		if type(service.OwlDestroy) == "function" then
			pcall(service.OwlDestroy, service)
		end
 
		if service._trove then
			service._trove:Destroy()
		end
	end
	
	if IsServer then
		local ok, OwlServer = pcall(require, script.OwlServer)
		
		if ok then
			OwlServer.Destroy()
		end
		
	elseif IsClient then
		local ok, OwlClient = pcall(require, script.OwlClient)
		
		if ok then
			OwlClient.Destroy()
		end
 
		if Owl.Util.Action then
			Owl.Util.Action._DestroyAll()
		end
	end
	
	OwlShared.Destroy()
	
	table.clear(_services)
	table.clear(_controllers)
	table.clear(_tokens)
	table.clear(_onPlayerAddedListeners)
	table.clear(_onPlayerRemovingListeners)
	table.clear(_onCharacterAddedListeners)
	table.clear(_onCharacterRemovingListeners)
	
	_onStartSignal:Destroy()
	_onStartSignal = Signal.new()
	
	_started = false
	_starting = false
end

-- > // Func : Inject Client Proxy \\ < --

function Owl._InjectClientServiceProxy(name: string, proxy: ServiceProxy)
	assert(IsClient, "[Owl] _InjectClientServiceProxy can only be called on the client.")
	assert(not _services[name], ("[Owl] Service proxy %q already injected."):format(name))
	_services[name] = (proxy :: any) :: RegisteredService
end

-- > // Funcs : Registries \\ < --

function Owl._GetServiceRegistry(): {[string]: RegisteredService}
	return _services
end

--

function Owl._GetControllerRegistry(): {[string]: RegisteredController}
	assert(IsClient, "[Owl] _GetControllerRegistry can only be called on the client.")
	return _controllers
end

return Owl