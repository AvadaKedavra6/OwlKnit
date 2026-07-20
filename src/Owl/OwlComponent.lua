--[[
				Owl - Component
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--

local Trove = require(script.Parent.Parent.Libs.Trove)
local Signal = require(script.Parent.Parent.Libs.Signal)
local Promise = require(script.Parent.Parent.Libs.Promise)

--

local IsClient = RunService:IsClient()
local IsServer = RunService:IsServer()

--

local Component = {}
Component.__index = Component

-- > // Types \\ < --

export type ComponentType = "Server" | "Client" | "Shared"
export type ComponentInstance = any
export type ComponentClassKey = any

--

export type ExtensionHooks = {
	Constructing: ((component: ComponentInstance) -> ())?,
	Constructed: ((component: ComponentInstance) -> ())?,
	Starting: ((component: ComponentInstance) -> ())?,
	Started: ((component: ComponentInstance) -> ())?,
	Stopping: ((component: ComponentInstance) -> ())?,
	Stopped: ((component: ComponentInstance) -> ())?,
}

--

export type Extension = {
	Name: string,
	Hooks: ExtensionHooks,
	[string]: unknown,
}

--

export type ComponentConfig = {
	Tag: string,
	Type: ComponentType,
	Ancestors: {Instance}?,
	Extensions: {Extension}?,
}

--

local ActiveComponents: {[any]: {[Instance]: any}} = {}

-- > // Func : Is Context Allowed \\ < --

local function isContextAllowed(componentType: ComponentType): boolean
	if componentType == "Shared" then
		return true
	elseif componentType == "Server" then
		return IsServer
	elseif componentType == "Client" then
		return IsClient
	end
	
	return false
end

-- > // Func : Current Context \\ < --

local function currentContextName(): string
	return IsServer and "Server" or "Client"
end

-- > // Func : Fire Extension \\ < --

local function fireExtensionHook(extensions: {Extension}, hook: string, component: ComponentInstance)
	for _, ext in ipairs(extensions) do
		local fn = ext.Hooks and ext.Hooks[hook]
		
		if type(fn) == "function" then
			local ok, err = pcall(fn, component)
			
			if not ok then
				warn(("[Owl - Component] Extension %q hook %q errored: %s"):format(tostring(ext.Name), hook, tostring(err)))
			end
		end
	end
end

-- > // Func : Valid Ancestor \\ < --

local function isValidAncestor(instance: Instance, ancestors: {Instance}?): boolean
	if not ancestors or #ancestors == 0 then
		return true
	end

	for _, ancestor in ipairs(ancestors) do
		if instance:IsDescendantOf(ancestor) then
			return true
		end
	end

	return false
end

-- > // Func : new \\ < --

function Component.new(config: ComponentConfig)
	assert(type(config.Tag) == "string" and #config.Tag > 0, "[Owl - Component] 'Tag' must be a non empty string.")
	assert(config.Type == "Server" or config.Type == "Client" or config.Type == "Shared", ("[Owl - Component] 'Type' must be 'Server', 'Client' or 'Shared'. Got: %q"):format(tostring(config.Type)))
	local self = setmetatable({}, Component)

	self._tag = config.Tag
	self._type = config.Type :: ComponentType
	self._ancestors = config.Ancestors  or {}
	self._extensions = config.Extensions or {}
	self._instances = {} :: {[Instance]: ComponentInstance}
	self._masterTrove = Trove.new()
	self._started = false
	self._allowed = isContextAllowed(config.Type)

	--
	
	self.Added = Signal.new()
	self.Removed = Signal.new()
	ActiveComponents[self] = self._instances

	return self
end

-- > // Func : Get \\ < --

function Component:Get(instance: Instance): ComponentInstance?
	if not self._allowed then return nil end
	return self._instances[instance]
end

-- > // Func : Get All \\ < --

function Component:GetAll(): {ComponentInstance}
	if not self._allowed then return {} end

	local result = {}
	
	for _, comp in pairs(self._instances) do
		table.insert(result, comp)
	end
	
	return result
end

-- > // Func ; Wait for \\ < --

function Component:WaitFor(instance: Instance, timeout: number?): ComponentInstance
	if not self._allowed then
		return Promise.reject(("[Owl - Component] WaitFor called on a %q component from %s context."):format(self._type, currentContextName()))
	end

	local existing = self._instances[instance]
	if existing then
		return Promise.resolve(existing)
	end

	return Promise.new(function(resolve, reject)
		local conn: RBXScriptConnection
		local timeoutThread: thread?

		conn = self.Added:Connect(function(inst, comp)
			if inst == instance then
				if timeoutThread then task.cancel(timeoutThread) end
				conn:Disconnect()
				resolve(comp)
			end
		end)

		if timeout then
			timeoutThread = task.delay(timeout, function()
				conn:Disconnect()
				reject(("[Owl - Component] WaitFor timeout (%ds) for tag %q on %q"):format(timeout, self._tag, instance.Name))
			end)
		end
	end)
end

-- > // Func : Construct Instyance \\ < --

function Component:_constructInstance(instance: Instance)
	if self._instances[instance] then return end
	if not isValidAncestor(instance, self._ancestors) then return end

	local obj = setmetatable({}, { __index = self })
	obj.Instance = instance
	obj._trove = Trove.new()
	obj._active = false

	obj._trove:Add(instance.Destroying:Connect(function()
		self:_destroyInstance(instance)
	end))

	self._instances[instance] = obj
	fireExtensionHook(self._extensions, "Constructing", obj)

	if type(obj.Construct) == "function" then
		local ok, err = pcall(obj.Construct, obj)
		
		if not ok then
			warn(("[Owl - Component] Error in Construct — tag %q on %q: %s"):format(self._tag, instance.Name, tostring(err)))
			self:_destroyInstance(instance)
			
			return
		end
	end

	fireExtensionHook(self._extensions, "Constructed", obj)
	fireExtensionHook(self._extensions, "Starting", obj)

	if type(obj.Start) == "function" then
		local ok, err = pcall(obj.Start, obj)
		
		if not ok then
			warn(("[Owl - Component] Error in Start — tag %q on %q: %s"):format(self._tag, instance.Name, tostring(err)))
			self:_destroyInstance(instance)
			
			return
		end
	end

	fireExtensionHook(self._extensions, "Started", obj)
	obj._active = true
	
	self.Added:Fire(instance, obj)
end

-- > // Func : Destroy Instance \\ < --

function Component:_destroyInstance(instance: Instance)
	local obj = self._instances[instance]
	if not obj then return end
	
	self._instances[instance] = nil
	fireExtensionHook(self._extensions, "Stopping", obj)

	if type(obj.Destroy) == "function" then
		pcall(obj.Destroy, obj)
	end

	fireExtensionHook(self._extensions, "Stopped", obj)

	obj._trove:Destroy()
	obj._active = false

	self.Removed:Fire(instance)
end

-- > // Func : Watch \\ < --

function Component:Watch()
	if not self._allowed then
		warn(("[Owl - Component] Component %q is Type=%q but Watch() was called from %s. Skipping."):format(self._tag, self._type, currentContextName()))
		return
	end

	assert(not self._started, ("[Owl - Component] Component %q is already watching."):format(self._tag))
	self._started = true

	for _, instance in ipairs(CollectionService:GetTagged(self._tag)) do
		task.spawn(function()
			self:_constructInstance(instance)
		end)
	end

	self._masterTrove:Add(
		CollectionService:GetInstanceAddedSignal(self._tag):Connect(function(instance)
			task.spawn(function()
				self:_constructInstance(instance)
			end)
		end)
	)

	self._masterTrove:Add(
		CollectionService:GetInstanceRemovedSignal(self._tag):Connect(function(instance)
			self:_destroyInstance(instance)
		end)
	)
end

-- > // Func : Stop \\ < --

function Component:Stop()
	if not self._started then return end

	for instance in pairs(self._instances) do
		self:_destroyInstance(instance)
	end

	self._masterTrove:Destroy()
	self._masterTrove = Trove.new()
	self._started = false

	ActiveComponents[self] = nil
end

-- > // Func : Destroy \\ < --

function Component:Destroy()
	self:Stop()
	self.Added:Destroy()
	self.Removed:Destroy()
end

-- > // Func ; Owl new \\ < --

local OwlComponent = {}

function OwlComponent.new(config: ComponentConfig): ComponentClassKey
	return Component.new(config)
end

-- > // Func : Owl Create Extension \\ < --

function OwlComponent.CreateExtension(ext: Extension): Extension
	assert(type(ext.Name) == "string" and #ext.Name > 0, "[Owl - Component] Extension must have a non empty 'Name'.")
	assert(type(ext.Hooks) == "table", "[Owl - Component] Extension must have a 'Hooks' table.")
	return ext
end

-- > // Func : Owl Get Component \\ < --

function OwlComponent.GetAllOfType(componentClass: ComponentClassKey): {ComponentInstance}
	local instances = ActiveComponents[componentClass]
	if not instances then return {} end

	local result = {}
	
	for _, comp in pairs(instances) do
		table.insert(result, comp)
	end
	
	return result
end

-- > // Func Owl Get \\ < --

function OwlComponent.Get(instance: Instance, componentClass: ComponentClassKey): ComponentInstance
	local instances = ActiveComponents[componentClass]
	if not instances then return nil end
	return instances[instance]
end

-- > // Func : Owl Get One Component \\ < --

function OwlComponent._GetRegistry(): {[ComponentClassKey]: {[Instance]: ComponentInstance}}
	return ActiveComponents
end

return OwlComponent