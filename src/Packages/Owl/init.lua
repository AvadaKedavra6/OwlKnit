--[[
				Owl - Main
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

--

local Promise = require(RepStorage.Packages.Libs.Promise)
local Signal = require(RepStorage.Packages.Libs.Signal)
local Trove = require(RepStorage.Packages.Libs.Trove)
local Timer = require(RepStorage.Packages.Libs.Timer)

local OwlShared = require(script.OwlShared)
local Log = OwlShared.Logger("Owl")

-- > // Types \\ < --

export type MiddlewareFn = (plr: Player, args: {any}) -> (boolean, ...any)
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
	Client: {[string]: any}?,
	[string]: any,
}

--

export type ControllerConfig = {
	Name: string,
	Dependencies: {string}?,
	[string]: any,
}

--

type RegisteredService = {
	Name: string,
	Dependencies: {string},
	Middleware: {Inbound: Middleware, Outbound: Middleware},
	Client: {[string]: any},
	OwlInit: ((self: any) -> ())?,
	OwlStart: ((self: any) -> ())?,
	_comm: any,
	[string]: any,
}

--

type RegisteredController = {
	Name: string,
	Dependencies: {string},
	OwlInit: ((self: any) -> ())?,
	OwlStart: ((self: any) -> ())?,
	[string]: any,
}

-- > // Others Variables \\ < --

local _started = false
local _starting = false
local _services: {[string]: RegisteredService} = {}
local _controllers: {[string]: RegisteredController} = {}
local _tokens: {[Player]: string} = {}

--

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
	TypeChecker = require(RepStorage.Packages.Middleware.TypeChecker),
	RateLimiter = require(RepStorage.Packages.Middleware.RateLimiter),
	Component = require(script.OwlComponent),
	Data = IsServer and require(script.OwlData) or nil,
	Action = IsClient and require(script.OwlAction) or nil,
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
			(service :: any)[k] = v 
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
			(controller :: any)[k] = v 
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
	local o = opts or {}
	
	return {
		_owlType = "Signal",
		_unreliable = (o :: any).unreliable or false,
		_inbound = (o :: any).inbound or {},
		_outbound = (o :: any).outbound or {},
	}
end

-- > // Func : Create Property \\ < --

function Owl.CreateProperty<T>(initialValue: T, opts: {inbound: Middleware?, outbound: Middleware?}?)
	local o = opts or {}
	
	return {
		_owlType = "Property",
		_initial = initialValue,
		_inbound = (o :: any).inbound or {},
		_outbound = (o :: any).outbound or {},
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
			local registry: {[string]: {Dependencies: {string}, [string]: any}}

			if IsServer then
				registry = Owl._GetServiceRegistry() :: any
			else
				registry = Owl._GetControllerRegistry() :: any
			end

			local sorted, sortErr = OwlShared.TopologicalSort(registry)
			if sortErr then
				reject(sortErr)
				return
			end

			local items: {any} = {}
			for _, name in ipairs(sorted) do
				table.insert(items, registry[name])
			end

			Log.info("Starting OwlInit phase (%d items)...", #items)

			return OwlShared.RunPhase(
				items,
				function(item)
					if type(item.OwlInit) == "function" then
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
					function(item)
						if type(item.OwlStart) == "function" then
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
	
	_onStartSignal:Destroy()
	_onStartSignal = Signal.new()
	
	_started = false
	_starting = false
end

-- > // Func : Inject Client Proxy \\ < --

function Owl._InjectClientServiceProxy(name: string, proxy: any)
	assert(IsClient, "[Owl] _InjectClientServiceProxy can only be called on the client.")
	assert(not _services[name], ("[Owl] Service proxy %q already injected."):format(name))
	_services[name] = proxy
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