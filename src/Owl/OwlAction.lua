--[[
				Owl - Action
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")

--

local Trove = require(script.Parent.Parent.Libs.Trove)
local Signal = require(script.Parent.Parent.Libs.Signal)

--

local OwlShared = require(script.Parent.OwlShared)
local Log = OwlShared.Logger("Action")

--

local OwlAction = {}
local ActionMap = {}
ActionMap.__index = ActionMap

--

local _registry: {[string]: any} = {}
local _activeStack: {any} = {}
local _bindCounter = 0

-- > // Types \\ < --

export type ActionState = "Begin" | "Change" | "End"
export type ActionCallback = (state: ActionState, inputObject: InputObject) -> ()
export type ExtensionHooks = {
	Enabling: ((map: any) -> ())?,
	Enabled: ((map: any) -> ())?,
	Disabling: ((map: any) -> ())?,
	Disabled: ((map: any) -> ())?,
}

-- > // Func : State to String \\ < --

local function stateToString(inputState: Enum.UserInputState): ActionState
	if inputState == Enum.UserInputState.Begin then
		return "Begin"
	elseif inputState == Enum.UserInputState.End then
		return "End"
	end

	return "Change"
end

-- > // Func : Next Cas Name \\ < --

local function nextCasName(mapName: string, actionName: string): string
	_bindCounter += 1
	return ("OwlAction_%s_%s_%d"):format(mapName, actionName, _bindCounter)
end

-- > // Func : Extension Hooks \\ < --

local function runExtensionHook(map: any, hookName: string)
	for _, ext in ipairs(map._extensions) do
		local hook = ext.Hooks and ext.Hooks[hookName]

		if type(hook) == "function" then
			local ok, err = pcall(hook, map)

			if not ok then
				Log.warn("[Owl - Action] Extension %q failed on hook %q for ActionMap %q: %s", tostring(ext.Name), hookName, map.Name, tostring(err))
			end
		end
	end
end

-- > // Func : Create Action \\ < --

function OwlAction.CreateActionMap(config: {Name: string, Actions: {[string]: any}}, Priority: number?, CreateTouchButtons: boolean?, Extensions: {any}?, ...)
	assert(type(config.Name) == "string" and #config.Name > 0, "[Owl] ActionMap requires a non empty Name.")
	assert(type(config.Actions) == "table", "[Owl] ActionMap requires an Actions table.")
	assert(not _registry[config.Name], ("[Owl - Action] ActionMap %q already exists."):format(config.Name))
	
	local self = setmetatable({}, ActionMap)
	
	self.Name = config.Name
	self.StateChanged = Signal.new()

	self._actions = config.Actions
	self._priority = config.Priority or Enum.ContextActionPriority.Default.Value
	self._createTouchButtons = config.CreateTouchButtons ~= false
	self._extensions = config.Extensions or {}
	self._callbacks = {}
	self._casNames = {}
	self._trove = Trove.new()
	self._enabled = false

	self._trove:Add(self.StateChanged)
	_registry[self.Name] = self

	return self
end

-- > // Func : Create Extension \\ < --

function OwlAction.CreateExtension(ext: {Name: string, Hooks: ExtensionHooks})
	assert(type(ext.Name) == "string", "[Owl - Action] Extension requires a Name.")
	assert(type(ext.Hooks) == "table", "[Owl - Action] Extension requires a Hooks table.")
	return ext
end

-- > // Func : Bind \\ < --

function ActionMap:Bind(actionName: string, fn: ActionCallback): () -> ()
	assert(self._actions[actionName], ("[Owl - Action] ActionMap %q has no action %q."):format(self.Name, actionName))

	self._callbacks[actionName] = self._callbacks[actionName] or {}
	local list = self._callbacks[actionName]
	table.insert(list, fn)

	return function()
		local idx = table.find(list, fn)
		if idx then table.remove(list, idx) end
	end
end

-- > // Func : Dispatch \\ < --

function ActionMap:_dispatch(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
	local state = stateToString(inputState)
	self.StateChanged:Fire(actionName, state, inputObject)

	local list = self._callbacks[actionName]
	if not list or #list == 0 then
		return Enum.ContextActionResult.Pass
	end

	for _, fn in ipairs(list) do
		task.spawn(fn, state, inputObject)
	end

	return Enum.ContextActionResult.Sink
end

-- > // Func : Enable \\ < --

function ActionMap:Enable()
	if self._enabled then return end
	runExtensionHook(self, "Enabling")

	for actionName, inputs in pairs(self._actions) do
		local casName = nextCasName(self.Name, actionName)
		self._casNames[actionName] = casName

		CAS:BindActionAtPriority(
			casName,
			
			function(_actionNameCas: string, inputState: Enum.UserInputState, inputObject: InputObject)
				return self:_dispatch(actionName, inputState, inputObject)
			end,
			
			self._createTouchButtons,
			
			self._priority,
			
			table.unpack(inputs)
		)
	end

	self._enabled = true
	table.insert(_activeStack, self)
	
	runExtensionHook(self, "Enabled")
	Log.info("ActionMap %q enabled (priority %d).", self.Name, self._priority)
end

-- > // Func : Disable \\ < --

function ActionMap:Disable()
	if not self._enabled then return end
	runExtensionHook(self, "Disabling")

	for _, casName in pairs(self._casNames) do
		CAS:UnbindAction(casName)
	end

	table.clear(self._casNames)
	self._enabled = false

	local idx = table.find(_activeStack, self)
	if idx then table.remove(_activeStack, idx) end

	runExtensionHook(self, "Disabled")
	Log.info("ActionMap %q disabled.", self.Name)
end

-- > // Func : Get State \\ < --

function ActionMap:GetState(actionName: string): boolean
	local inputs = self._actions[actionName]
	if not inputs then
		Log.warn("GetState: unknown action %q on ActionMap %q.", actionName, self.Name)
		return false
	end

	for _, input in ipairs(inputs) do
		if typeof(input) == "EnumItem" and input.EnumType == Enum.KeyCode then
			if UIS:IsKeyDown(input) then return true end

		elseif typeof(input) == "EnumItem" and input.EnumType == Enum.UserInputType then
			if input.Name:match("^MouseButton") then
				if UIS:IsMouseButtonPressed(input) then return true end
			end
		end
	end

	return false
end

-- > // Func : Is Enabled \\ < --

function ActionMap:IsEnabled(): boolean
	return self._enabled
end

-- > // Func : Destroy \\ < --

function ActionMap:Destroy()
	self:Disable()
	self._trove:Destroy()
	_registry[self.Name] = nil
end

-- > //Func : Get Action Map \\ < --

function OwlAction.GetActionMap(name: string)
	return _registry[name]
end

-- > // Func : Get Active \\ < --

function OwlAction.GetActive(): {any}
	return table.clone(_activeStack)
end

-- > // func : Disable all \\ < --

function OwlAction.DisableAll()
	for _, map in ipairs(table.clone(_activeStack)) do
		map:Disable()
	end
end

-- > // Func : Dezstroy All \\ < --

function OwlAction._DestroyAll()
	for _, map in pairs(table.clone(_registry)) do
		map:Destroy()
	end

	table.clear(_registry)
	table.clear(_activeStack)
end

return OwlAction