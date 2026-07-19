--[[
				Owl - Shared
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
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

-- > // Func : Inject Config \\ < --

function OwlShared.InjectConfig(config: {Verbose: boolean})
	_config = config
end

-- > // Func : Logger \\ < --

function OwlShared.Logger(scope: string)
	assert(type(scope) == "string" and #scope > 0, "[Owl] Logger scope must be a non empty string.")
	local prefix = string.format("[Owl - %s - %s] ", ContextLabel, scope)

	return {
		info = function(msg: string, ...)
			if not _config.Verbose then return end
			print(prefix .. " " .. msg:format(...))
		end,

		warn = function(msg: string, ...)
			warn(prefix .. " " .. msg:format(...))
		end,

		error = function(msg: string, ...)
			error(prefix .. " " .. msg:format(...), 2)
		end,
	}
end

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