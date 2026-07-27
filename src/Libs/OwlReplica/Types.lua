--[[
				OwlReplica - Types
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Types \\ < --

export type Path = {string | number}
export type SetListener<V> = (new_value: V, old_value: V?, changed_path: Path) -> ()
export type ArrayInsertListener<V> = (new_index: number, new_value: V) -> ()
export type ArraySetListener<V> = (index: number, new_value: V) -> ()
export type ArrayRemoveListener<V> = (old_index: number, old_value: V) -> ()
export type WriteListener<A...> = (A...) -> ()
export type DestroyListener = () -> ()

--

export type ActionCall<A...> = (A...) -> ()
export type ActionImpl<T, A, TagT, Args...> = (replica: OwlReplica<T, A, TagT>, Args...) -> ()
export type ActionsImplTable<T, A, TagT> = {[string]: (OwlReplica<T, A, TagT>, ...any) -> ()}

--

export type OwlReplicaParams<T, A = {}, TagT = { [string]: any }> = {
	Token: string,
	Data: T,
	Tags: TagT?,
	Parent: OwlReplica<any, any, any>?,
	Actions: ActionsImplTable<T, A, TagT>?,
}

export type ReplicationScope = "None" | "Everyone" | "Selective"

--

export type OwlReplica<T, A = {}, TagT = {[string]: any }> = {
	Id: number,
	Token: string,
	Tags: TagT,
	Data: T,
	Parent: OwlReplica<any, any, any>?,
	Children: { [number]: OwlReplica<any, any, any> },

	SetValue: <V>(self: OwlReplica<T, A, TagT>, path: Path, value: V) -> (),
	SetValues: (self: OwlReplica<T, A, TagT>, path: Path, values: { [string]: any }) -> (),
	ArrayInsert: <V>(self: OwlReplica<T, A, TagT>, path: Path, value: V) -> number,
	ArraySet: <V>(self: OwlReplica<T, A, TagT>, path: Path, index: number, value: V) -> (),
	ArrayRemove: <V>(self: OwlReplica<T, A, TagT>, path: Path, index: number) -> V?,

	Actions: A,
	Write: (self: OwlReplica<T, A, TagT>, action_name: string, ...any) -> (),

	Replicate: (self: OwlReplica<T, A, TagT>) -> (),
	ReplicateFor: (self: OwlReplica<T, A, TagT>, player: Player) -> (),
	DestroyFor: (self: OwlReplica<T, A, TagT>, player: Player) -> (),

	AddCleanupTask: (self: OwlReplica<T, A, TagT>, task: (() -> ()) | { Destroy: (any) -> () }) -> (),
	Destroy: (self: OwlReplica<T, A, TagT>) -> (),

	ListenToFullChange: (self: OwlReplica<T, A, TagT>, listener: FullChangeListener<T>, comparator: ValueComparator?) -> () -> (),
	ListenToChange: <V>(self: OwlReplica<T, A, TagT>, path: Path, listener: SetListener<V>) -> () -> (),
	ListenToArrayInsert: <V>(self: OwlReplica<T, A, TagT>, path: Path, listener: ArrayInsertListener<V>) -> () -> (),
	ListenToArraySet: <V>(self: OwlReplica<T, A, TagT>, path: Path, listener: ArraySetListener<V>) -> () -> (),
	ListenToArrayRemove: <V>(self: OwlReplica<T, A, TagT>, path: Path, listener: ArrayRemoveListener<V>) -> () -> (),
	ListenToWrite: (self: OwlReplica<T, A, TagT>, action_name: string, listener: WriteListener<...any>) -> () -> (),

	OnDestroy: (self: OwlReplica<T, A, TagT>, listener: DestroyListener) -> () -> (),
}

--

export type CreationPayload = {
	Id: number,
	Token: string,
	Data: any,
	ParentId: number?,
}

--

export type MutationKind = "Set" | "SetValues" | "ArrayInsert" | "ArraySet" | "ArrayRemove"

export type MutationEntry = {
	Kind: MutationKind,
	Path: Path?,
	Value: any?,
	Index: number?,
}

export type MutationBatch = {
	Id: number,
	Mutations: { MutationEntry },
}

--

export type ChangeRecord = {
	Path: Path,
	OldValue: any,
	NewValue: any,
}

--

export type FullChangeListener<T> = (data: T, changes: { ChangeRecord }) -> ()
export type ValueComparator = (old_value: any, new_value: any) -> boolean

return {}