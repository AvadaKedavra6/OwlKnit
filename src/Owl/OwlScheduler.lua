--[[
				Owl - Scheduler
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")

--

local OwlShared = require(script.Parent.OwlShared)
local Log = OwlShared.Logger("Scheduler")

--

local IsClient = RunService:IsClient()
local DefaultBudgetMS = 2
local DefaultTaskCostMS = 0.05
local FrameEmaAlpha = 0.1

--

local OwlScheduler = {}

local _nextId = 0
local _budgetMs = DefaultBudgetMS
local _lastFrameMs = 0
local _avgFrameMs = 0
local _taskQueue: {Task} = {}
local _frameQueue: {Task} = {}
local _renderQueue: {Task} = {}
local _deferredQueue: {Task} = {}


-- > // Types \\ < --

export type TaskFn = (dt: number) -> boolean? 

--

export type TaskOptions = {
	Priority: number?,
	Delay: number?,
	Interval: number?,
	Repeat: number?,
	BudgetCost: number?,
}

--

export type TaskHandle = {
	Cancel: (self: TaskHandle) -> (),
	Destroy: (self: TaskHandle) -> (),
	IsRunning: (self: TaskHandle) -> boolean,
}
 
--

type Task = {
	Id: number,
	Fn: TaskFn,
	Priority: number,
	Interval: number?,
	Repeat: number?,
	BudgetCost: number,
	NextRun: number,
	RunCount: number,
	Cancelled: boolean,
}

--

export type SchedulerStats = {
	BudgetMs: number,
	LastFrameMs: number,
	AverageFrameMs: number,
	TaskQueueLength: number,
	FrameQueueLength: number,
	RenderQueueLength: number,
	DeferredQueueLength: number,
}

-- > // Func : Run Task Safe \\ < --

local function runTaskSafely(task: Task, dt: number): boolean?
	task.RunCount += 1
	local ok, result = pcall(task.Fn, dt)
 
	if not ok then
		Log.warn("Scheduled task #%d errored: %s", task.Id, tostring(result))
		return nil
	end
 
	return result
end

-- > // Func : Drain Queue \\ < --

local function drainQueue(queue: {Task}, dt: number, now: number, hasBudget: ((cost: number) -> boolean)?)
	if #queue == 0 then return end
	table.sort(queue, function(a, b) return a.Priority < b.Priority end)
 
	local i = 1
	while i <= #queue do
		local task = queue[i]
 
		if task.Cancelled then
			table.remove(queue, i)
			continue
		end
 
		if now < task.NextRun then
			i += 1
			continue
		end
 
		if hasBudget and not hasBudget(task.BudgetCost) then
			break 
		end
 
		local stop = runTaskSafely(task, dt)
 
		if task.Interval then
			task.NextRun = now + task.Interval
 
			if stop == true or (task.Repeat and task.RunCount >= task.Repeat) then
				task.Cancelled = true
			end
		else
			task.Cancelled = true
		end
 
		if task.Cancelled then
			table.remove(queue, i)
		else
			i += 1
		end
	end
end

-- > // Func : Handle \\ < --

local function makeHandle(task: Task): TaskHandle
	local handle = {}
 
	handle.Cancel = function(_self: TaskHandle)
		task.Cancelled = true
	end
 
	handle.Destroy = handle.Cancel
 
	handle.IsRunning = function(_self: TaskHandle): boolean
		return not task.Cancelled
	end
 
	return handle :: TaskHandle
end

-- > // Func : Enqueue \\ < --

local function enqueue(queue: {Task}, fn: TaskFn, opts: TaskOptions?): TaskHandle
	_nextId += 1
	local o = opts or {}
 
	local task: Task = {
		Id = _nextId,
		Fn = fn,
		Priority = o.Priority or 0,
		Interval = o.Interval,
		Repeat = o.Repeat,
		BudgetCost = o.BudgetCost or DefaultTaskCostMS,
		NextRun = os.clock() + (o.Delay or 0),
		RunCount = 0,
		Cancelled = false,
	}
 
	table.insert(queue, task)
	return makeHandle(task)
end

-- > // Func : Add \\ < --

function OwlScheduler:Add(fn: TaskFn, opts: TaskOptions?): TaskHandle
	return enqueue(_taskQueue, fn, opts)
end

-- > // Func : Every \\ < --

function OwlScheduler:Every(interval: number, fn: TaskFn, opts: TaskOptions?): TaskHandle
	assert(type(interval) == "number" and interval >= 0, "[Owl - Scheduler] Every expects a non negative interval.")

	local merged: TaskOptions = if opts then table.clone(opts) else {}
	merged.Interval = interval

	return enqueue(_taskQueue, fn, merged)
end

-- > // Func : Next Frame \\ < --

function OwlScheduler:NextFrame(fn: TaskFn, opts: TaskOptions?): TaskHandle
	return enqueue(_frameQueue, fn, opts)
end

-- > // Func : On Render \\ < --

function OwlScheduler:OnRender(fn: TaskFn, opts: TaskOptions?): TaskHandle
	assert(IsClient, "[Owl - Scheduler] OnRender can only be used on the client.")
	return enqueue(_renderQueue, fn, opts)
end

-- > // Func : Defer \\ < --

function OwlScheduler:Defer(fn: TaskFn, opts: TaskOptions?): TaskHandle
	return enqueue(_deferredQueue, fn, opts)
end

-- > // Func : Until \\ < --

function OwlScheduler:Until(fn: (dt: number) -> boolean, opts: TaskOptions?): TaskHandle
	local merged: TaskOptions = if opts then table.clone(opts) else {}
	merged.Interval = merged.Interval or 0
	return enqueue(_taskQueue, fn, merged)
end

-- > // Func : Set Budget \\ < --

function OwlScheduler:SetBudget(ms: number)
	assert(type(ms) == "number" and ms > 0, "[Owl - Scheduler] Budget must be a positive number.")
	_budgetMs = ms
end

-- > // Func : Get Budget \\ < --

function OwlScheduler:GetBudget(): number
	return _budgetMs
end

-- > // Func : Get Stats \\ < --

function OwlScheduler:GetStats(): SchedulerStats
	return {
		BudgetMs = _budgetMs,
		LastFrameMs = _lastFrameMs,
		AverageFrameMs = _avgFrameMs,
		TaskQueueLength = #_taskQueue,
		FrameQueueLength = #_frameQueue,
		RenderQueueLength = #_renderQueue,
		DeferredQueueLength = #_deferredQueue,
	}
end

-- > // Func : On Heartbeat \\ < --

local function onHeartbeat(dt: number)
	local frameStart = os.clock()
	local now = os.clock()
 
	drainQueue(_frameQueue, dt, now, nil)
 
	local budgetStart = os.clock()
	local function hasBudget(cost: number): boolean
		return ((os.clock() - budgetStart) * 1000) + cost <= _budgetMs
	end
 
	drainQueue(_taskQueue, dt, now, hasBudget)
	drainQueue(_deferredQueue, dt, now, hasBudget)

	_lastFrameMs = (os.clock() - frameStart) * 1000
	_avgFrameMs = _avgFrameMs + FrameEmaAlpha * (_lastFrameMs - _avgFrameMs)
end

-- > // Func : On Render Stepped \\ < --

local function onRenderStepped(dt: number)
	drainQueue(_renderQueue, dt, os.clock(), nil)
end

--

local _heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
local _renderConn: RBXScriptConnection? = if IsClient then RunService.RenderStepped:Connect(onRenderStepped) else nil

-- > // Func : Destroy \\ < --

function OwlScheduler._Destroy()
	if _heartbeatConn then _heartbeatConn:Disconnect() end
	if _renderConn then _renderConn:Disconnect() end

	_lastFrameMs = 0
	_avgFrameMs = 0
 
	table.clear(_taskQueue)
	table.clear(_frameQueue)
	table.clear(_renderQueue)
	table.clear(_deferredQueue)
end
 
return OwlScheduler