--[[
				Owl - Shared
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")

--

local Promise = require(script.Parent.Parent.Libs.Promise)
local isServer = RunService:IsServer()

--

local OwlShared = {}

--

local _config: {Verbose: boolean} = {Verbose = false}
local ContextLabel = isServer and "Server" or "Client"

-- > // Types \\ < --

export type LogLevel = "Trace" | "Debug" | "Info" | "Success" | "Warn" | "Error"

--

export type LogEntry = {
	Timestamp: string,
	Context: string,
	Scope: string,
	Level: LogLevel,
	Message: string,
}

--

type LogFormatFn = (entry: LogEntry) -> string
type LoggerLike = {warn: (msg: string, ...unknown) -> ()}

-- > // Funcs : Logs \\ < --

local LevelOrder: {[LogLevel]: number} = {
	Trace = 1, Debug = 2, Info = 3, Success = 3, Warn = 4, Error = 5,
}

--
 
local LevelTag: {[LogLevel]: string} = {
	Trace = "TRACE", Debug = "DEBUG", Info = "INFO", Success = "SUCCESS", Warn = "WARN", Error = "ERROR",
}

--

local function timestamp(): string
	local dt = DateTime.now()
	local millis = dt.UnixTimestampMillis % 1000
	return os.date("%H:%M:%S", dt.UnixTimestamp) .. string.format(".%03d", millis)
end

--

local function defaultFormat(entry: LogEntry): string
	return string.format("[%s] | [%s - %s] | [%s] %s", entry.Timestamp, entry.Scope, entry.Context, LevelTag[entry.Level], entry.Message)
end

-- > // Func : Logger new \\ < --

local Logger = {}
Logger.__index = Logger

--

function Logger.new(scope: string)
	assert(type(scope) == "string" and #scope > 0, "[Owl] Logger scope must be a non empty string.")
 
	local self = setmetatable({}, Logger)
	self._scope = scope
	self._muted = false
	self._minLevel = nil :: number?
	self._format = defaultFormat
 
	self.info = function(msg: string, ...: unknown)
		self:_emit("Info", msg, ...)
	end
 
	self.warn = function(msg: string, ...: unknown)
		self:_emit("Warn", msg, ...)
	end
 
	self.error = function(msg: string, ...: unknown)
		self:_emit("Error", msg, ...)
	end
 
	return self
end

-- > // Func : Should Log \\ < --

function Logger:_shouldLog(level: LogLevel): boolean
	if self._muted then return false end
	local minLevel = self._minLevel or (if _config.Verbose then LevelOrder.Info else LevelOrder.Warn)
	return LevelOrder[level] >= minLevel
end

-- > // Func : Emit \\ < --

function Logger:_emit(level: LogLevel, msg: string, ...: unknown)
	if not self:_shouldLog(level) then return end
 
	local ok, formatted = pcall(string.format, msg, ...)
	local text = if ok then formatted else msg
 
	local entry: LogEntry = {
		Timestamp = timestamp(),
		Context = ContextLabel,
		Scope = self._scope,
		Level = level,
		Message = text,
	}
 
	local line = self._format(entry)
 
	if level == "Error" then
		error(line, 3)
	elseif level == "Warn" then
		warn(line)
	else
		print(line)
	end
end

-- > // Funcs : Level methods \\ < --

function Logger:Trace(msg: string, ...: unknown)
	self:_emit("Trace", msg, ...)
end

--
 
function Logger:Debug(msg: string, ...: unknown)
	self:_emit("Debug", msg, ...)
end

--
 
function Logger:Info(msg: string, ...: unknown)
	self:_emit("Info", msg, ...)
end

--
 
function Logger:Success(msg: string, ...: unknown)
	self:_emit("Success", msg, ...)
end

--
 
function Logger:Warn(msg: string, ...: unknown)
	self:_emit("Warn", msg, ...)
end

--
 
function Logger:Error(msg: string, ...: unknown)
	self:_emit("Error", msg, ...)
end

-- > // Func : Set Level \\ < --

function Logger:SetLevel(level: LogLevel)
	self._minLevel = LevelOrder[level]
end

-- > // Func : Set Format \\ < --

function Logger:SetFormat(fn: LogFormatFn)
	self._format = fn
end

-- > // Funcs : Mute/Unmute \\ < --

function Logger:Mute()
	self._muted = true
end

--
 
function Logger:Unmute()
	self._muted = false
end

-- > // Func : Child \\ < --

function Logger:Child(name: string)
	assert(type(name) == "string" and #name > 0, "[Owl] Logger:Child name must be a non empty string.")
 
	local child = Logger.new(self._scope .. "." .. name)
	child._minLevel = self._minLevel
	child._format = self._format
	child._muted = self._muted
 
	return child
end

setmetatable(Logger, {
	__call = function(_, scope: string)
		return Logger.new(scope)
	end,
})

export type LoggerInstance = typeof(Logger.new(""))
 
-- > // Func : Inject Config \\ < --

function OwlShared.InjectConfig(config: {Verbose: boolean})
	_config = config
end

-- > // Func : Logger \\ < --

OwlShared.Logger = Logger

-- > // Func : Hash Name \\ < --

function OwlShared.HashName(name: string): string
	assert(type(name) == "string", "[Owl] HashName expects a string.")
	local hash = 5381
	
	for i = 1, #name do
		hash = bit32.band(bit32.lshift(hash, 5) + hash + string.byte(name, i), 0xFFFFFFFF)
	end
	
	return string.format("%08x", hash)
end

-- > // Func : New Token \\ < --

local _tokenCounter = 0
local _sessionStamp = tostring(math.floor(os.clock() * 1000))

function OwlShared.NewToken(): string
	_tokenCounter += 1
	return ("%s_%05d"):format(_sessionStamp, _tokenCounter)
end

-- > // Func : Load Modules \\ < --

function OwlShared.LoadModules(folder: Folder, log: any?)
	assert(typeof(folder) == "Instance", "[Owl] LoadModules expects an Instance as folder.")

	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("ModuleScript") then
			local ok, err = pcall(require, obj)
			
			if not ok then
				if log then
					log.warn("Failed to load module %q: %s", obj.Name, tostring(err))
				else
					warn(("[Owl - Shared] Failed to load module %q: %s"):format(obj.Name, tostring(err)))
				end
			end
		end
	end
end

-- > // Func : Topo Sort \\ < --

function OwlShared.TopologicalSort(registry: {[string]: {Dependencies: {string}}}): ({string}, string?)
	local sorted: {string} = {}
	local visited: {[string]: boolean} = {}
	local visiting: {[string]: boolean} = {}
	local cycleErr: string? = nil

	local function visit(name: string)
		if cycleErr then return end
		if visited[name]  then return end

		if visiting[name] then
			cycleErr = ("[Owl] Dependency cycle detected involving: %q"):format(name)
			return
		end

		visiting[name] = true

		local entry = registry[name]
		if entry then
			for _, dep in ipairs(entry.Dependencies or {}) do
				if not registry[dep] then
					cycleErr = ("[Owl] %q has unknown dependency: %q"):format(name, dep)
					return
				end
				
				visit(dep)
			end
		end

		visiting[name] = nil
		visited[name]  = true
		table.insert(sorted, name)
	end

	for name in pairs(registry) do
		visit(name)
		
		if cycleErr then
			return {}, cycleErr
		end
	end

	return sorted, nil
end

-- > // Func : Run Phase \\ < --

function OwlShared.RunPhase(items: {any}, fn: (item: any) -> (), phase: string, timeout: number, mode: "sequential" | "parallel")
	return Promise.new(function(resolve, reject)
		local count = #items
		if count == 0 then resolve() return end

		local timedOut  = false
		local timeoutThread: thread

		timeoutThread = task.delay(timeout, function()
			timedOut = true
			reject(("[Owl] Timeout (%ds) in phase %q. Check for infinite yields."):format(timeout, phase))
		end)

		if mode == "sequential" then
			task.spawn(function()
				for _, item in ipairs(items) do
					if timedOut then return end
					local ok, err = pcall(fn, item)
					
					if not ok then
						task.cancel(timeoutThread)
						reject(("[Owl] Error during %s in %q: %s"):format(phase, tostring(item.Name), tostring(err)))
						return
					end
				end

				if not timedOut then
					task.cancel(timeoutThread)
					resolve()
				end
			end)

		else
			local completed = 0
			local failed = false

			for _, item in ipairs(items) do
				task.spawn(function()
					if failed or timedOut then return end
					local ok, err = pcall(fn, item)
					if failed or timedOut then return end

					if not ok then
						failed = true
						task.cancel(timeoutThread)
						reject(("[Owl] Error during %s in %q: %s"):format(phase, tostring(item.Name), tostring(err)))
						return
					end

					completed += 1
					
					if completed == count then
						task.cancel(timeoutThread)
						resolve()
					end
				end)
			end
		end
	end)
end

-- > // Func : Destroy \\ < --

function OwlShared.Destroy()
	_tokenCounter = 0
	_config = {Verbose = false}
end

return OwlShared