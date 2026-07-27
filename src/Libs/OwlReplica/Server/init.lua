--[[
				OwlReplica - Server
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local Players = game:getService("Players")
local NameSpace = "OwlKnit_Replica"

--

local Comm = require(script.Parent.Parent.Comm)
local Types = require(script.Parent.Types)
local PathUtils = require(script.Parent.PathUtils)

--

local ServerComm = Comm.ServerComm.new(script.Parent, NameSpace)
local SigOwlReplicaCreated = ServerComm:CreateSignal("OwlReplicaCreated")
local SigOwlReplicaMutation = ServerComm:CreateSignal("OwlReplicaMutation")
local SigOwlReplicaDestroyed = ServerComm:CreateSignal("OwlReplicaDestroyed")
local SigRequestData = ServerComm:CreateSignal("RequestData")

--

local next_id = 0
local owlreplicas: {[number]: any} = {}
local playersready: {[Player]: boolean} = {}
local dirty_replicas: { [number]: any } = {}
local network_heartbeat_conn: RBXScriptConnection? = nil

--

local OwlReplicaServer = {}
OwlReplicaServer.__index = OwlReplicaServer

-- > // Types \\ < --

type Path = Types.Path
type OwlReplica<T, A, TagT> = Types.OwlReplica<T, A, TagT>
type OwlReplicaParams<T, A, TagT> = Types.OwlReplicaParams<T, A, TagT>
type MutationBatch = Types.MutationBatch

-- > // Func : Send Batch \\ < --

local function sendBatch(internal, player: Player, batch: MutationBatch)
	SigOwlReplicaMutation:Fire(player, batch)
end

-- > // Func : Network Mutation \\ < --

local function flushNetworkMutations()
	for id, internal in dirty_replicas do
		local pending = internal.pending_network_mutations

		if #pending > 0 then
			local batch: MutationBatch = { Id = id, Mutations = pending }
			internal.pending_network_mutations = {}

			if internal.scope == "Everyone" then
				SigOwlReplicaMutation:FireAll(batch)
			elseif internal.scope == "Selective" then
				for player in internal.replicated_for do
					if playersready[player] then
						sendBatch(internal, player, batch)
					end
				end
			end
		end

		dirty_replicas[id] = nil
	end

	if network_heartbeat_conn then
		network_heartbeat_conn:Disconnect()
		network_heartbeat_conn = nil
	end
end

-- > // Func : Queue Mutation \\ < --

local function queueMutation(internal, entry: Types.MutationEntry)
	if internal.scope == "None" then
		return
	end

	table.insert(internal.pending_network_mutations, entry)
	dirty_replicas[internal.public.Id] = internal

	if not network_heartbeat_conn then
		network_heartbeat_conn = RunService.Heartbeat:Connect(flushNetworkMutations)
	end
end

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

-- > // Func : Should Replicate To \\ < --

local function shouldReplicateTo(internal, plr: Player): boolean
	if internal.scope == "Everyone" then
		return true
	elseif internal.scope == "Selective" then
		return internal.replicated_for[plr] == true
	end

	return false
end

-- > // Func : Send Creation \\ < --

local function sendCreation(internal, plr: Player)
	SigOwlReplicaCreated:Fire(plr, {
		Id = internal.public.Id,
		Token = internal.public.Token,
		Data = internal.public.Data,
		ParentId = internal.public.Parent and (internal.public.Parent :: any).Id or nil,
	} :: Types.CreationPayload)
end

-- > // Funcs : Connect/Disconnect \\ < --

SigRequestData:Connect(function(plr: Player)
	playersready[plr] = true

	for _, internal in owlreplicas do
		if shouldReplicateTo(internal, plr) then
			sendCreation(internal, plr)
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	playersready[plr] = nil

	for _, internal in owlreplicas do
		internal.replicated_for[plr] = nil
	end
end)

-- > // Funcs : Helpers \\ < --

local DefaultComparator = function(old_value, new_value)
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

-- > // Func : New \\ < --

function OwlReplicaServer.New<T, A, TagT>(params: OwlReplicaParams<T, A, TagT>): OwlReplica<T, A, TagT>
	next_id += 1
	local id = next_id

	local internal = {
		scope = "None" :: Types.ReplicationScope,
		replicated_for = {} :: {[Player]: boolean},
		cleanup_tasks = {} :: {any},
		change_listeners = newPathListenerRegistry(),
		array_insert_listeners = newPathListenerRegistry(),
		array_set_listeners = newPathListenerRegistry(),
		array_remove_listeners = newPathListenerRegistry(),
		write_listeners = {} :: {[string]: {(...any) -> ()}},
		pending_network_mutations = {} :: {Types.MutationEntry},
		pending_changes = {} :: { any },
		full_change_listeners = {} :: {{listener: (any, any) -> (), comparator: (any, any) -> boolean}},
		heartbeat_conn = nil :: RBXScriptConnection?,
		destroy_bus = newEventBus(),
		action_impls = params.Actions or {},
	}

	local self = setmetatable({
		Id = id,
		Token = params.Token,
		Tags = params.Tags or {},
		Data = params.Data,
		Parent = params.Parent,
		Children = {},
		Actions = {} :: any,
	}, OwlReplicaServer) :: any

	internal.public = self
	self._internal = internal

	for action_name, impl in internal.action_impls do
		self.Actions[action_name] = function(...: any)
			impl(self, ...)

			local listeners = internal.write_listeners[action_name]
			if listeners then
				for _, fn in listeners do
					task.spawn(fn, ...)
				end
			end
		end
	end

	owlreplicas[id] = internal

	if params.Parent then
		table.insert((params.Parent :: any).Children, self)
	end

	return self
end

-- > // Funcs : Replications \\ < --

function OwlReplicaServer:Replicate()
	local internal = self._internal
	internal.scope = "Everyone"

	for _, plr in Players:GetPlayers() do
		if playersready[plr] then
			sendCreation(internal, plr)
		end
	end
end

--

function OwlReplicaServer:ReplicateFor(plr: Player)
	local internal = self._internal

	if internal.scope == "None" then
		internal.scope = "Selective"
	end

	internal.replicated_for[plr] = true

	if playersready[plr] then
		sendCreation(internal, plr)
	end
end

--

function OwlReplicaServer:ReplicateForList(player_list: {Player})
	for _, plr in player_list do
		self:ReplicateFor(plr)
	end
end

--

function OwlReplicaServer:DestroyFor(plr: Player)
	local internal = self._internal
	internal.replicated_for[plr] = nil
	SigOwlReplicaDestroyed:Fire(plr, {Id = self.Id})
end

--

function OwlReplicaServer:IsReplicatedFor(plr: Player): boolean
	return shouldReplicateTo(self._internal, plr)
end

-- > // Funcs : Mutations \\ < --

function OwlReplicaServer:SetValue(path: Path, value: any)
	local old_value = PathUtils.Set(self.Data, path, value)
	local internal = self._internal

	queueMutation(internal, {Kind = "Set", Path = path, Value = value})
	internal.change_listeners:FireBubbled(path, {value, old_value}, {path})
	recordChange(internal, path, old_value, value)
end

--

function OwlReplicaServer:SetValues(path: Path, values: {[string]: any})
	local target = PathUtils.Get(self.Data, path)
	assert(type(target) == "table", "[OwlKnitReplica] SetValues: path is not a table.")

	for k, v in values do
		target[k] = v
	end

	local internal = self._internal
	queueMutation(internal, {Kind = "SetValues", Path = path, Value = values})
end

--

function OwlReplicaServer:ArrayInsert(path: Path, value: any): number
	local new_index = PathUtils.ArrayInsert(self.Data, path, value)
	local internal = self._internal

	queueMutation(internal, {Kind = "ArrayInsert", Path = path, Value = value, Index = new_index})
	internal.array_insert_listeners:FireExact(path, new_index, value)
	recordChange(internal, path, nil, value)

	return new_index
end

--

function OwlReplicaServer:ArraySet(path: Path, index: number, value: any)
	local array = PathUtils.Get(self.Data, path)
	local old_value = array and array[index] or nil
	PathUtils.ArraySet(self.Data, path, index, value)
	local internal = self._internal

	queueMutation(internal, {Kind = "ArraySet", Path = path, Value = value, Index = index})
	internal.array_set_listeners:FireExact(path, index, value)
	recordChange(internal, path, old_value, value)
end

--

function OwlReplicaServer:ArrayRemove(path: Path, index: number): any
	local removed = PathUtils.ArrayRemove(self.Data, path, index)
	local internal = self._internal

	queueMutation(internal, {Kind = "ArrayRemove", Path = path, Index = index})
	internal.array_remove_listeners:FireExact(path, index, removed)
	recordChange(internal, path, removed, nil)

	return removed
end

--

function OwlReplicaServer:GetData(path: Path): any
	return PathUtils.Get(self.Data, path)
end

--

function OwlReplicaServer:Write(action_name: string, ...: any)
	local action_fn = self.Actions[action_name]
	assert(action_fn, `[OwlKnitReplica] Action unknown: "{action_name}"`)
	action_fn(...)
end

-- > // Funcs : Listeners \\ < --

function OwlReplicaServer:ListenToChange(path: Path, listener: (any, any?, Path) -> ()): () -> ()
	return self._internal.change_listeners:Add(path, listener)
end

--

function OwlReplicaServer:ListenToFullChange(listener: (any, any) -> (), comparator: ((any, any) -> boolean)?): () -> ()
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

function OwlReplicaServer:ListenToArrayInsert(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_insert_listeners:Add(path, listener)
end

--

function OwlReplicaServer:ListenToArraySet(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_set_listeners:Add(path, listener)
end

--

function OwlReplicaServer:ListenToArrayRemove(path: Path, listener: (number, any) -> ()): () -> ()
	return self._internal.array_remove_listeners:Add(path, listener)
end

--

function OwlReplicaServer:ListenToWrite(action_name: string, listener: (...any) -> ()): () -> ()
	local internal = self._internal
	internal.write_listeners[action_name] = internal.write_listeners[action_name] or {}

	table.insert(internal.write_listeners[action_name], listener)

	return function()
		local list = internal.write_listeners[action_name]

		if list then
			local idx = table.find(list, listener)

			if idx then
				table.remove(list, idx)
			end
		end
	end
end

--

function OwlReplicaServer:OnDestroy(listener: () -> ()): () -> ()
	return self._internal.destroy_bus:Connect(listener)
end

--

function OwlReplicaServer:AddCleanupTask(cleanup_task: any)
	table.insert(self._internal.cleanup_tasks, cleanup_task)
end

-- > // Funcs : Destructors \\ < --

function OwlReplicaServer:Destroy()
	local internal = self._internal
	if internal.destroyed then return end
	internal.destroyed = true

	for _, child in self.Children do
		(child :: any):Destroy()
	end

	if internal.scope == "Everyone" then
		SigOwlReplicaDestroyed:FireAll({ Id = self.Id })
	elseif internal.scope == "Selective" then
		for player in internal.replicated_for do
			SigOwlReplicaDestroyed:Fire(player, { Id = self.Id })
		end
	end

	for _, cleanup_task in internal.cleanup_tasks do
		if type(cleanup_task) == "function" then
			cleanup_task()
		elseif type(cleanup_task) == "table" and cleanup_task.Destroy then
			cleanup_task:Destroy()
		end
	end

	if internal.heartbeat_conn then
		internal.heartbeat_conn:Disconnect()
		internal.heartbeat_conn = nil
	end

	internal.destroy_bus:Fire()
	dirty_replicas[self.Id] = nil
	owlreplicas[self.Id] = nil
end

return {
    New = OwlReplicaServer.New,
}