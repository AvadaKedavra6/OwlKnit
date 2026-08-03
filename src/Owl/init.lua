--[[
				Owl - Main
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")

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
local AddonLog = OwlShared.Logger("Addons")

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
	Version: string?,
	[string]: unknown,
}

--

export type ControllerConfig = {
	Name: string,
	Dependencies: {string}?,
	OwlInit: ((self: RegisteredController) -> ())?,
	OwlStart: ((self: RegisteredController) -> ())?,
	Version: string?,
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
	Version: string?,
	_comm: CommLike?,
	_trove: TroveLike?,
	_remoteKinds: {[string]: "Signal" | "Property" | "Function"}?,
	[string]: unknown,
}

--

type RegisteredController = {
	Name: string,
	Dependencies: {string},
	OwlInit: ((self: RegisteredController) -> ())?,
	OwlStart: ((self: RegisteredController) -> ())?,
	Version: string?,
	[string]: unknown,
}

--

type LifecycleItem = {
	Name: string,
	Dependencies: {string},
	OwlInit: ((self: LifecycleItem) -> ())?,
	OwlStart: ((self: LifecycleItem) -> ())?,
}

--

export type ItemMetrics = {
	InitTime: number?,
	StartTime: number?,
	MemoryKb: number?,
	Started: boolean?,
}

--

export type ServiceInfo = {
	Name: string,
	Dependencies: {string},
	Started: boolean,
	InitTime: number?,
	StartTime: number?,
	Hooks: {string},
	ClientRemotes: {string},
	Memory: number?,
	Version: string,
}

--

export type ControllerInfo = {
	Name: string,
	Dependencies: {string},
	Started: boolean,
	InitTime: number?,
	StartTime: number?,
	Hooks: {string},
	Memory: number?,
	Version: string,
}

--

export type MetricsSummary = {
	Services: number,
	ServicesStarted: number,
	Controllers: number,
	ControllersStarted: number,
	ComponentClasses: number,
	ComponentInstances: number,
	Signals: number,
	Properties: number,
	Actions: number,
	AverageInitTime: number,
	AverageStartTime: number,
	MemoryMb: number,
	SchedulerBudgetMs: number,
	SchedulerAverageFrameMs: number,
}

--
 
export type ServiceMetrics = {
	Init: number?,
	Start: number?,
	Memory: number?,
	Signals: number,
	Properties: number,
	Functions: number,
}

--
 
export type ControllerMetrics = {
	Init: number?,
	Start: number?,
	Memory: number?,
}

--

export type AddonAPI = {
	Version: string,
	Config: StartConfig,
	Util: {[string]: unknown},
	CreateService: (config: ServiceConfig) -> RegisteredService,
	CreateController: (config: ControllerConfig) -> RegisteredController,
	CreateSignal: (opts: {unreliable: boolean?, inbound: Middleware?, outbound: Middleware?}?) -> unknown,
	CreateProperty: (initialValue: unknown, opts: {inbound: Middleware?, outbound: Middleware?}?) -> unknown,
	GetService: (name: string) -> unknown,
	GetController: (name: string) -> unknown,
	GetProvider: (slotName: string) -> Addon?,
	GetAddon: (name: string) -> Addon?,
	Reflection: {[string]: unknown},
	Metrics: {[string]: unknown},
	Trove: TroveLike,
	Logger: OwlShared.LoggerInstance,
}

--

export type AddonHooks = {
	Init: ((self: Addon, owl: AddonAPI) -> ())?,
	OnServiceRegistered: ((self: Addon, service: RegisteredService) -> ())?,
	OnControllerRegistered: ((self: Addon, controller: RegisteredController) -> ())?,
	OnFrameworkStarting: ((self: Addon) -> ())?,
	OnFrameworkStarted: ((self: Addon) -> ())?,
	OnFrameworkDestroying: ((self: Addon) -> ())?,
}

--

export type Addon = {
	Name: string,
	Priority: number?,
	Dependencies: {string}?,
	OptionalDependencies: {string}?,
	OwlVersion: string?,
	Provides: string?,
	Version: string?,
	Author: string?,
	Description: string?,
	Hooks: AddonHooks,
	[string]: unknown,
}

--

type AddonMetrics = {
	InitTime: number?,
	InitError: string?,
	Started: boolean,
}

--

export type AddonInfo = {
	Name: string,
	Version: string,
	Author: string,
	Description: string,
	Dependencies: {string},
	OptionalDependencies: {string},
	Provides: string?,
	Started: boolean,
	InitTime: number?,
	InitError: string?,
}

-- > // Others Variables \\ < --

local _started = false
local _starting = false
local _registrationLocked = false
local _services: {[string]: RegisteredService} = {}
local _controllers: {[string]: RegisteredController} = {}
local _tokens: {[Player]: string} = {}
local _addons: {Addon} = {}
local _metrics: {[string]: ItemMetrics} = {}
local _addonMetrics: {[string]: AddonMetrics} = {}
local _addonTroves: {[string]: TroveLike} = {} 

--

local _onStartSignal = Signal.new()

--

local Owl = {}

Owl.Version = "1.1.2"

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
	Scheduler = require(script.OwlScheduler),
	Replica = require(script.Parent.Libs.OwlReplica),
	ListenerGroup = require(script.Parent.Libs.OwlReplica.ListenerGroup), -- > // It's come from Replica
	Flags = require(script.OwlFlag),
}

-- > // Funcs : Parse Version \\ < --

local function parseVersion(v: string): (number, number, number)
	local major, minor, patch = v:match("(%d+)%.?(%d*)%.?(%d*)")
	return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
end

--

local function compareVersions(a: string, b: string): number
	local aMaj, aMin, aPat = parseVersion(a)
	local bMaj, bMin, bPat = parseVersion(b)
 
	if aMaj ~= bMaj then return if aMaj < bMaj then -1 else 1 end
	if aMin ~= bMin then return if aMin < bMin then -1 else 1 end
	if aPat ~= bPat then return if aPat < bPat then -1 else 1 end

	return 0
end

-- > // Func : Check Requirements \\ < --

local function checkVersionRequirement(requirement: string, actual: string): boolean
	local op, version = requirement:match("^([<>=]*)%s*(.+)$")
	if not version then return false end

	op = if op ~= "" then op else "="
	local cmp = compareVersions(actual, version)
	
	if op == ">=" then 
		return cmp >= 0
	elseif op == "<=" then 
		return cmp <= 0
	elseif op == ">" then 
		return cmp > 0
	elseif op == "<" then 
		return cmp < 0
	elseif op == "=" or op == "==" then 
		return cmp == 0
	end
 
	return false
end

-- > // Func : Fire Addon Hook \\ < --

local function fireAddonHook(hookName: string, ...: unknown)
	local sorted = table.clone(_addons)
	table.sort(sorted, function(a, b)
		return (a.Priority or 0) < (b.Priority or 0)
	end)
 
	for _, addon in ipairs(sorted) do
		local hook = (addon.Hooks :: any)[hookName]
 
		if type(hook) == "function" then
			local ok, err = pcall(hook, addon, ...)
 
			if not ok then
				AddonLog.warn("Addon %q errored on hook %q: %s", addon.Name, hookName, tostring(err))
			end
		end
	end
end

-- > // Func : Register Addon \\ < --

function Owl.RegisterAddon(addon: Addon): Addon
	assert(type(addon.Name) == "string" and #addon.Name > 0, "[Owl] Addon must have a non empty 'Name'.")
	assert(type(addon.Hooks) == "table", "[Owl] Addon must have a 'Hooks' table.")
	assert(not _started and not _starting, ("[Owl] Cannot register addon %q after Owl.Start() has been called."):format(addon.Name))
 
	for _, existing in ipairs(_addons) do
		assert(existing.Name ~= addon.Name, ("[Owl] An addon named %q is already registered."):format(addon.Name))
	end
 
	if addon.OwlVersion then
		assert(
			checkVersionRequirement(addon.OwlVersion, Owl.Version),
			("[Owl] Addon %q requires Owl %s, but this project runs Owl %s."):format(addon.Name, addon.OwlVersion, Owl.Version)
		)
	end
 
	table.insert(_addons, addon)
	AddonLog.info("Addon %q registered (priority %d).", addon.Name, addon.Priority or 0)
 
	return addon
end

-- > // Func : GetAddon \\ < --
 
function Owl.GetAddon(name: string): Addon?
	for _, addon in ipairs(_addons) do
		if addon.Name == name then
			return addon
		end
	end
 
	return nil
end

-- > // Func : Build API for addon \\ < --

local function buildAddonAPI(addon: Addon): AddonAPI
	local shared = (Owl :: any) :: AddonAPI
 
	local addonTrove = Trove.new()
	_addonTroves[addon.Name] = addonTrove
 
	local api = setmetatable({
		Trove = addonTrove,
		Logger = OwlShared.Logger("Addon." .. addon.Name),
	}, {__index = shared})
 
	return (api :: any) :: AddonAPI
end

-- > // Func : Run Adddon Inits \\ < --

local function runAddonInits(sortedNames: {string})
	return Promise.new(function(resolve)
		local items: {Addon} = {}
		for _, name in ipairs(sortedNames) do
			local addon = Owl.GetAddon(name)

			if addon then
				table.insert(items, addon)
			end
		end
 
		if #items == 0 then
			resolve()
			return
		end
 
		local timedOut = false
		local timeoutThread = task.delay(Owl.Config.InitTimeout, function()
			timedOut = true
			AddonLog.warn("Addon Init phase exceeded %ds timeout remaining addons skipped, framework starts anyway.", Owl.Config.InitTimeout)
			resolve()
		end)
 
		task.spawn(function()
			for _, addon in ipairs(items) do
				if timedOut then break end
 
				local hook = addon.Hooks.Init
				local clockBefore = os.clock()
				local ok: boolean, err: unknown = true, nil
 
				if type(hook) == "function" then
					local api = buildAddonAPI(addon)
					ok, err = pcall(hook, addon, api)
				end
 
				_addonMetrics[addon.Name] = {
					InitTime = (os.clock() - clockBefore) * 1000,
					InitError = if not ok then tostring(err) else nil,
					Started = ok,
				}
 
				if not ok then
					AddonLog.warn("Addon %q errored during Init: %s", addon.Name, tostring(err))
				end
			end
 
			if not timedOut then
				task.cancel(timeoutThread)
				resolve()
			end
		end)
	end)
end

-- > // Func : Create Service \\ < --

function Owl.CreateService(config: ServiceConfig): RegisteredService
	assert(IsServer, "[Owl] CreateService can only be called on the server.")
	assert(type(config.Name) == "string" and #config.Name > 0, "[Owl] Service must have a non empty name.")
	assert(not _started and not _registrationLocked, ("[Owl] Cannot create service %q: the registration window has closed (services must be created before Owl.Start() or from an addon's Init hook)."):format(config.Name))
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
	fireAddonHook("OnServiceRegistered", service)
	
	return service
end

-- > // Func : Create Controller \\ < --

function Owl.CreateController(config: ControllerConfig): RegisteredController
	assert(IsClient, "[Owl] CreateController can only be called on the client.")
	assert(type(config.Name) == "string" and #config.Name > 0, "[Owl] Controller must have a non empty name.")
	assert(not _started and not _registrationLocked, ("[Owl] Cannot create controller %q: the registration window has closed (controllers must be created before Owl.Start() or from an addon's Init hook)."):format(config.Name))
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
	fireAddonHook("OnControllerRegistered", controller)
	
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

function Owl.GetPlrToken(plr)
    local token = _tokens[plr]

	if not token then
		token = OwlShared.NewToken()
		_tokens[plr] = token
	end

	return token
end

function Owl._SetPlrToken(plr, token)
    _tokens[plr] = token
end

function Owl._ClearPlrToken(plr: Player)
	_tokens[plr] = nil
end

-- > // Func : Start \\ < --

function Owl.Start(startConfig: StartConfig?)
	assert(not _started and not _starting, "[Owl] Owl.Start() has already been called.")

	local addonsFolder = script:FindFirstChild("Addons")
	if addonsFolder then
		OwlShared.LoadModules(addonsFolder, Log)
	end

	_starting = true
 
	if startConfig then
		if startConfig.Verbose ~= nil then Owl.Config.Verbose = startConfig.Verbose end
		if startConfig.InitTimeout ~= nil then Owl.Config.InitTimeout = startConfig.InitTimeout end
		if startConfig.StartTimeout ~= nil then Owl.Config.StartTimeout = startConfig.StartTimeout end
		if startConfig.GlobalMiddleware ~= nil then Owl.Config.GlobalMiddleware = startConfig.GlobalMiddleware end
	end
 
	OwlShared.InjectConfig(Owl.Config)

	local addonRegistry: {[string]: {Dependencies: {string}}} = {}
	for _, addon in ipairs(_addons) do
		local deps = table.clone(addon.Dependencies or {})
 
		for _, optionalDep in ipairs(addon.OptionalDependencies or {}) do
			if Owl.GetAddon(optionalDep) then
				table.insert(deps, optionalDep)
			end
		end
 
		addonRegistry[addon.Name] = {Dependencies = deps}
	end

	local sortedAddonNames, addonSortErr = OwlShared.TopologicalSort(addonRegistry)
	if addonSortErr then
		_starting = false
		return Promise.reject(addonSortErr)
	end

	return runAddonInits(sortedAddonNames):andThen(function()
		_registrationLocked = true

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
			fireAddonHook("OnFrameworkStarting")
			local registry: {[string]: any}
 
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
					local memBefore = collectgarbage("count")
					local clockBefore = os.clock()
 
					if item.OwlInit then
						item:OwlInit()
					end
 
					_metrics[item.Name] = {
						InitTime = (os.clock() - clockBefore) * 1000,
						MemoryKb = collectgarbage("count") - memBefore,
					}
				end,
				"OwlInit",
				Owl.Config.InitTimeout,
				"sequential"
 
			):andThen(function()
				Log.info("Starting OwlStart phase (%d items)...", #items)
 
				return OwlShared.RunPhase(
					items,
					function(item: any)
						local clockBefore = os.clock()
 
						if item.OwlStart then
							item:OwlStart()
						end
 
						local metrics = _metrics[item.Name] or {}
						metrics.StartTime = (os.clock() - clockBefore) * 1000
						metrics.Started = true
						_metrics[item.Name] = metrics
					end,
					"OwlStart",
					Owl.Config.StartTimeout,
					"parallel"
				)
 
			end):andThen(function()
				_started = true
				_starting = false
				
				table.freeze(Owl.Config)
 
				Log.info("Framework started successfully.")
				print("[Owl] Framework started successfully.")
 
				fireAddonHook("OnFrameworkStarted")
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

	fireAddonHook("OnFrameworkDestroying")
	Owl.Util.Scheduler._Destroy()
	
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
	table.clear(_addons)
	table.clear(_addonMetrics)

	for _, trove in pairs(_addonTroves) do
		trove:Destroy()
	end

	table.clear(_addonTroves)
	table.clear(_metrics)
	
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

-- > // [Reflection] Variables \\ < --

Owl.Reflection = {}

--

local ServiceHookNames = {
	"OwlInit", "OwlStart", "OwlDestroy", 
	"OwlOnPlayerAdded", "OwlOnPlayerRemoving",
	"OwlOnCharacterAdded", "OwlOnCharacterRemoving",
	"OwlOnSpawnReady",
}

local ControllerHookNames = {
	"OwlInit", "OwlStart", "OwlDestroy",
	"OwlOnCharacterAdded", "OwlOnCharacterRemoving",
	"OwlOnPlayerCharacterReady", "OwlOnLocalPlayerReady", "OwlOnPlayerLeft",
}

-- > // [Reflection] Func : Get Services \\ < --

function Owl.Reflection.GetServices(): {string}
	assert(IsServer, "[Owl] Reflection.GetServices can only be called on the server.")
 
	local names = {}
	for name in pairs(_services) do
		table.insert(names, name)
	end
 
	table.sort(names)
	return names
end

-- > // [Reflection] Func : Get Service Info \\ < --

function Owl.Reflection.GetServiceInfo(name: string): ServiceInfo?
	assert(IsServer, "[Owl] Reflection.GetServiceInfo can only be called on the server.")
 
	local service = _services[name]
	if not service then return nil end
 
	local hooks = {}
	for _, hookName in ipairs(ServiceHookNames) do
		if type(service[hookName]) == "function" then
			table.insert(hooks, hookName)
		end
	end
 
	local remotes = {}
	if type(service.Client) == "table" then
		for key in pairs(service.Client) do
			table.insert(remotes, key)
		end
		table.sort(remotes)
	end
 
	local metrics = _metrics[name]
 
	return {
		Name = service.Name,
		Dependencies = service.Dependencies,
		Started = (metrics and metrics.Started) or false,
		InitTime = metrics and metrics.InitTime,
		StartTime = metrics and metrics.StartTime,
		Hooks = hooks,
		ClientRemotes = remotes,
		Memory = metrics and metrics.MemoryKb,
		Version = service.Version or "1.0.0",
	}
end

-- > // [Reflection] Func : Get Controllers \\ < --

function Owl.Reflection.GetControllers(): {string}
	assert(IsClient, "[Owl] Reflection.GetControllers can only be called on the client.")
 
	local names = {}
	for name in pairs(_controllers) do
		table.insert(names, name)
	end
 
	table.sort(names)
	return names
end

-- > // [Reflection] Func : Get Controller Info \\ < --

function Owl.Reflection.GetControllerInfo(name: string): ControllerInfo?
	assert(IsClient, "[Owl] Reflection.GetControllerInfo can only be called on the client.")
 
	local controller = _controllers[name]
	if not controller then return nil end
 
	local hooks = {}
	for _, hookName in ipairs(ControllerHookNames) do
		if type(controller[hookName]) == "function" then
			table.insert(hooks, hookName)
		end
	end
 
	local metrics = _metrics[name]
 
	return {
		Name = controller.Name,
		Dependencies = controller.Dependencies or {},
		Started = (metrics and metrics.Started) or false,
		InitTime = metrics and metrics.InitTime,
		StartTime = metrics and metrics.StartTime,
		Hooks = hooks,
		Memory = metrics and metrics.MemoryKb,
		Version = controller.Version or "1.0.0",
	}
end

-- > // [Reflection] Func : Get Components \\ < --

function Owl.Reflection.GetComponents(): {string}
	local registry = Owl.Util.Component._GetRegistry()
	local tags: {string} = {}
 
	for componentClass in pairs(registry) do
		local tag = (componentClass :: any)._tag
 
		if type(tag) == "string" then
			table.insert(tags, tag)
		end
	end
 
	table.sort(tags)
	return tags
end

-- > // [Reflection] Func : Get Actions \\ < --

function Owl.Reflection.GetActions(): {string}
	local Action = Owl.Util.Action
 
	if not Action then
		return {}
	end
 
	local registry = Action._GetRegistry()
	local names: {string} = {}
 
	for actionMapName in pairs(registry) do
		table.insert(names, actionMapName)
	end
 
	table.sort(names)
	return names
end

-- > // [Reflection] Func : Collect Remotes \\ < --

local function collectRemotesByKind(kind: "Signal" | "Property"): {string}
	assert(IsServer, "[Owl] Reflection remote introspection (GetSignals/GetProperties) is only available on the server, the source of truth for remote kinds.")
 
	local result = {}
 
	for serviceName, service in pairs(_services) do
		local kinds = service._remoteKinds
 
		if kinds then
			for key, remoteKind in pairs(kinds) do
				if remoteKind == kind then
					table.insert(result, serviceName .. "." .. key)
				end
			end
		end
	end
 
	table.sort(result)
	return result
end

-- > // [Reflection] Func : Get Signals \\ < --

function Owl.Reflection.GetSignals(): {string}
	return collectRemotesByKind("Signal")
end

-- > // [Reflection] Func : Get Properties \\ < --

function Owl.Reflection.GetProperties(): {string}
	return collectRemotesByKind("Property")
end

-- > // [Reflection] Func : Get Addons \\ < --

function Owl.Reflection.GetAddons(): {string}
	local names = {}

	for _, addon in ipairs(_addons) do
		table.insert(names, addon.Name)
	end

	table.sort(names)
	return names
end

-- > // Func : Get Addon info \\ < --

function Owl.Reflection.GetAddonInfo(name: string): AddonInfo?
	local addon = Owl.GetAddon(name)
	if not addon then return nil end
 
	local metrics = _addonMetrics[name]
 
	return {
		Name = addon.Name,
		Version = addon.Version or "1.0.0",
		Author = addon.Author or "Unknown",
		Description = addon.Description or "",
		Dependencies = addon.Dependencies or {},
		OptionalDependencies = addon.OptionalDependencies or {},
		Provides = addon.Provides,
		Started = (metrics and metrics.Started) or false,
		InitTime = metrics and metrics.InitTime,
		InitError = metrics and metrics.InitError,
	}
end

-- > // [Metrics] Variables \\ < --

Owl.Metrics = {}

-- > // [Metrics] Func : Get Summary \\ < --

function Owl.Metrics.GetSummary(): MetricsSummary
	local serviceCount, servicesStarted = 0, 0
	local controllerCount, controllersStarted = 0, 0
	local initSum, initCount = 0, 0
	local startSum, startCount = 0, 0
	local signals, properties = 0, 0
 
	if IsServer then
		for name, service in pairs(_services) do
			serviceCount += 1
 
			local kinds = service._remoteKinds
			if kinds then
				for _, kind in pairs(kinds) do
					if kind == "Signal" then signals += 1
					elseif kind == "Property" then properties += 1 end
				end
			end
 
			local m = _metrics[name]
			if m then
				if m.Started then servicesStarted += 1 end
				if m.InitTime then initSum += m.InitTime; initCount += 1 end
				if m.StartTime then startSum += m.StartTime; startCount += 1 end
			end
		end
	end
 
	if IsClient then
		for name in pairs(_controllers) do
			controllerCount += 1
 
			local m = _metrics[name]
			if m then
				if m.Started then controllersStarted += 1 end
				if m.InitTime then initSum += m.InitTime; initCount += 1 end
				if m.StartTime then startSum += m.StartTime; startCount += 1 end
			end
		end
	end
 
	local componentClasses, componentInstances = 0, 0
	for _, instances in pairs(Owl.Util.Component._GetRegistry()) do
		componentClasses += 1

		for _ in pairs(instances) do
			componentInstances += 1
		end
	end
 
	local actionsCount = 0
	local Action = Owl.Util.Action
	if Action then
		for _ in pairs(Action._GetRegistry()) do
			actionsCount += 1
		end
	end
 
	local schedulerStats = Owl.Util.Scheduler:GetStats()
 
	return {
		Services = serviceCount,
		ServicesStarted = servicesStarted,
		Controllers = controllerCount,
		ControllersStarted = controllersStarted,
		ComponentClasses = componentClasses,
		ComponentInstances = componentInstances,
		Signals = signals,
		Properties = properties,
		Actions = actionsCount,
		AverageInitTime = if initCount > 0 then initSum / initCount else 0,
		AverageStartTime = if startCount > 0 then startSum / startCount else 0,
		MemoryMb = collectgarbage("count") / 1024,
		SchedulerBudgetMs = schedulerStats.BudgetMs,
		SchedulerAverageFrameMs = schedulerStats.AverageFrameMs,
	}
end

-- > // [Metrics] Func : Get Service Metrics \\ < --

function Owl.Metrics.GetServiceMetrics(name: string): ServiceMetrics?
	assert(IsServer, "[Owl] Metrics.GetServiceMetrics can only be called on the server.")
 
	local service = _services[name]
	if not service then return nil end
 
	local signals, properties, functions = 0, 0, 0
	local kinds = service._remoteKinds
 
	if kinds then
		for _, kind in pairs(kinds) do
			if kind == "Signal" then signals += 1
			elseif kind == "Property" then properties += 1
			elseif kind == "Function" then functions += 1 end
		end
	end
 
	local m = _metrics[name]
 
	return {
		Init = m and m.InitTime,
		Start = m and m.StartTime,
		Memory = m and m.MemoryKb,
		Signals = signals,
		Properties = properties,
		Functions = functions,
	}
end

-- > // [Metrics] Func : Get Controller Metrics \\ < --

function Owl.Metrics.GetControllerMetrics(name: string): ControllerMetrics?
	assert(IsClient, "[Owl] Metrics.GetControllerMetrics can only be called on the client.")
 
	local controller = _controllers[name]
	if not controller then return nil end
 
	local m = _metrics[name]
 
	return {
		Init = m and m.InitTime,
		Start = m and m.StartTime,
		Memory = m and m.MemoryKb,
	}
end

return Owl