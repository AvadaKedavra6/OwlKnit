--[[
				OwlReplica - Client
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local Comm = require(script.Parent.Parent.Comm)
local Types = require(script.Parent.Types)
local PathUtils = require(script.Parent.PathUtils)
local NameSpace = "OwlKnit_Replica"

--

local ClientComm = Comm.ClientComm.new(script.Parent, false, NameSpace)
local SigOwlReplicaCreated = ClientComm:GetSignal("OwlReplicaCreated")
local SigOwlReplicaMutation = ClientComm:GetSignal("OwlReplicaMutation")
local SigOwlReplicaDestroyed = ClientComm:GetSignal("OwlReplicaDestroyed")
local SigRequestData = ClientComm:GetSignal("RequestData")

--

local owlreplicas: {[number]: any} = {}
local tokenlisteners: {[string]: {(any) -> ()}} = {}
local requested = false

--

local OwlReplicaClient = {}
OwlReplicaClient.__index = OwlReplicaClient

-- > // Types \\ < --

type Path = Types.Path
type CreationPayload = Types.CreationPayload
type MutationBatch = Types.MutationBatch

-- > // Func : New Event bus \\ < --

local function newEventBus()
	local listeners: {(...any) -> ()} = {}

	return {
		Connect = function(_self, fn)
			table.insert(listeners, fn)

			return function()
				local idx = table.find(listeners, fn)

				if idx then
					table.remove(listeners, idx)
				end
			end
		end,

		Fire = function(_self, ...)
			for _, fn in listeners do
				task.spawn(fn, ...)
			end
		end,
	}
end

-- > // Func : New Path Reg \\ < --

local function newPathListenerRegistry()
	local by_key: {[string]: {(...any) -> ()}} = {}

	return {
		Add = function(_self, path: Path, listener: (...any) -> ())
			local key = PathUtils.ToKey(path)
			by_key[key] = by_key[key] or {}

			table.insert(by_key[key], listener)

			return function()
				local list = by_key[key]

				if list then
					local idx = table.find(list, listener)

					if idx then
						table.remove(list, idx)
					end
				end
			end
		end,

		FireExact = function(_self, path: Path, ...: any)
			local listeners = by_key[PathUtils.ToKey(path)]

			if listeners then
				for _, fn in listeners do
					task.spawn(fn, ...)
				end
			end
		end,

		FireBubbled = function(_self, path: Path, args: {any}, extra_args: {any}?)
			for _, key in PathUtils.PrefixKeys(path) do
				local listeners = by_key[key]

				if listeners then
					for _, fn in listeners do
						if extra_args then
							task.spawn(fn, table.unpack(args), table.unpack(extra_args))
						else
							task.spawn(fn, table.unpack(args))
						end
					end
				end
			end
		end,
	}
end

-- > // Funcs : Helpers \\ < --

local DefaultComparator = function(old_value: any, new_value: any): boolean
	return old_value ~= new_value
end

--

local function recordChange(internal, path: Path, old_value: any, new_value: any)
	if #internal.full_change_listeners == 0 then
		return
	end

	table.insert(internal.pending_changes, {Path = path, OldValue = old_value, NewValue = new_value})
end

--

local function flushFullChangeListeners(internal)
	if #internal.pending_changes == 0 then
		return
	end

	local changes = internal.pending_changes
	internal.pending_changes = {}

	for _, entry in internal.full_change_listeners do
		local filtered = {}

		for _, change in changes do
			if entry.comparator(change.OldValue, change.NewValue) then
				table.insert(filtered, change)
			end
		end

		if #filtered > 0 then
			task.spawn(entry.listener, internal.public.Data, filtered)
		end
	end
end

-- > // Funcs : Build Rep from payload \\ < --

local function buildReplicaFromPayload(payload: CreationPayload)
	local internal = {
		cleanup_tasks = {} :: {any},
		change_listeners = newPathListenerRegistry(),
		array_insert_listeners = newPathListenerRegistry(),
		array_set_listeners = newPathListenerRegistry(),
		array_remove_listeners = newPathListenerRegistry(),
		pending_changes = {} :: {any},
		full_change_listeners = {} :: {{listener: (any, any) -> (), comparator: (any, any) -> boolean}},
		heartbeat_conn = nil :: RBXScriptConnection?,
		destroy_bus = newEventBus(),
	}

	local parent = payload.ParentId and owlreplicas[payload.ParentId] or nil

	local self = setmetatable({
		Id = payload.Id,
		Token = payload.Token,
		Tags = {},
		Data = payload.Data,
		Parent = parent,
		Children = {},
	}, OwlReplicaClient) :: any

	self._internal = internal
	internal.public = self

	if parent then
		table.insert(parent.Children, self)
	end

	owlreplicas[payload.Id] = self
	return self
end

--

SigOwlReplicaCreated:Connect(function(payload: CreationPayload)
	local replica = buildReplicaFromPayload(payload)
	local listeners = tokenlisteners[replica.Token]

	if listeners then
		for _, fn in listeners do
			task.spawn(fn, replica)
		end
	end
end)

--

SigOwlReplicaMutation:Connect(function(batch: MutationBatch)
	local replica = owlreplicas[batch.Id]
	if not replica then
		warn(`[OwlReplica] Batch received by an stranger Replica (Id={batch.Id})`)
		return
	end
	local internal = replica._internal

	for _, entry in batch.Mutations do
		if entry.Kind == "Set" then
			local path = entry.Path :: Path
			local old_value = PathUtils.Set(replica.Data, path, entry.Value)
			internal.change_listeners:FireBubbled(path, { entry.Value, old_value }, { path })
			recordChange(internal, path, old_value, entry.Value)

		elseif entry.Kind == "SetValues" then
			local path = entry.Path :: Path
			local target = PathUtils.Get(replica.Data, path)
			for k, v in (entry.Value :: { [string]: any }) do
				target[k] = v
			end

		elseif entry.Kind == "ArrayInsert" then
			local path = entry.Path :: Path
			local array = PathUtils.Get(replica.Data, path)
			table.insert(array, entry.Index :: number, entry.Value)
			internal.array_insert_listeners:FireExact(path, entry.Index, entry.Value)
			recordChange(internal, path, nil, entry.Value)

		elseif entry.Kind == "ArraySet" then
			local path = entry.Path :: Path
			local array = PathUtils.Get(replica.Data, path)
			local old_value = array and array[entry.Index :: number] or nil
			PathUtils.ArraySet(replica.Data, path, entry.Index :: number, entry.Value)
			internal.array_set_listeners:FireExact(path, entry.Index, entry.Value)
			recordChange(internal, path, old_value, entry.Value)

		elseif entry.Kind == "ArrayRemove" then
			local path = entry.Path :: Path
			local removed = PathUtils.ArrayRemove(replica.Data, path, entry.Index :: number)
			internal.array_remove_listeners:FireExact(path, entry.Index, removed)
			recordChange(internal, path, removed, nil)
		end
	end
end)


--

SigOwlReplicaDestroyed:Connect(function(payload: { Id: number })
	local replica = owlreplicas[payload.Id]
	if not replica then return end
	local internal = replica._internal

	if internal.heartbeat_conn then
		internal.heartbeat_conn:Disconnect()
		internal.heartbeat_conn = nil
	end

	for _, cleanup_task in internal.cleanup_tasks do
		if type(cleanup_task) == "function" then
			cleanup_task()
		elseif type(cleanup_task) == "table" and cleanup_task.Destroy then
			cleanup_task:Destroy()
		end
	end

	internal.destroy_bus:Fire()
	owlreplicas[payload.Id] = nil
end)

-- > // Func : Replica Of Class Created \\ < --

local OwlPublic = {}

--

function OwlPublic.ReplicaOfClassCreated(token: string, listener: (replica: any) -> ())
	tokenlisteners[token] = tokenlisteners[token] or {}
	table.insert(tokenlisteners[token], listener)

	for _, replica in owlreplicas do
		if replica.Token == token then
			task.spawn(listener, replica)
		end
	end
end

-- > // Func : Request Data \\ < --

function OwlPublic.RequestData()
	if requested then return end
	requested = true
	SigRequestData:Fire()
end

-- > // Func : Get Replica By Id \\ < --

function OwlPublic.GetReplicaById(id: number): any?
    return owlreplicas[id]
end

-- > // Funcs : Listeners \\ < --

function OwlReplicaClient:ListenToChange(path: Path, listener: (any, any?, Path) -> ()): () -> ()
	return self._internal.change_listeners:Add(path, listener)
end

--

function OwlReplicaClient:ListenToFullChange(listener: (any, any) -> (), comparator: ((any, any) -> boolean)?): () -> ()
	local internal = self._internal
	local entry = {listener = listener, comparator = comparator or DefaultComparator}
	table.insert(internal.full_change_listeners, entry)

	if not internal.heartbeat_conn then
		internal.heartbeat_conn = RunService.Heartbeat:Connect(function()
			flushFullChangeListeners(internal)
		end)
	end

	return function()
		local idx = table.find(internal.full_change_listeners, entry)

		if idx then
			table.remove(internal.full_change_listeners, idx)
		end

		if #internal.full_change_listeners == 0 and internal.heartbeat_conn then
			internal.heartbeat_conn:Disconnect()
			internal.heartbeat_conn = nil
		end
	end
end

--

function OwlReplicaClient:ListenToArrayInsert(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_insert_listeners:Add(path, listener)
end

--

function OwlReplicaClient:ListenToArraySet(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_set_listeners:Add(path, listener)
end

--

function OwlReplicaClient:ListenToArrayRemove(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_remove_listeners:Add(path, listener)
end

--

function OwlReplicaClient:OnDestroy(listener: () -> ()): () -> ()
	return self._internal.destroy_bus:Connect(listener)
end

--

function OwlReplicaClient:AddCleanupTask(cleanup_task: any)
	table.insert(self._internal.cleanup_tasks, cleanup_task)
end

--

function OwlReplicaClient:GetData(path: Path): any
	return PathUtils.Get(self.Data, path)
end

return OwlPublic