--[[
				OwlReplica - ListenerGroup
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local ListenerGroup = {}
ListenerGroup.__index = ListenerGroup

-- > // Types \\ < --

export type Disconnector = () -> ()

-- > // Func : New \\ < --

function ListenerGroup.new()
    return setmetatable({
        _disconnectors = {} :: {Disconnector},
        _disconnected = false,
    }, ListenerGroup)
end

-- > // Func : Add \\ < --

function ListenerGroup:Add(disconnector: Disconnector): Disconnector
	if self._disconnected then
		disconnector()
		return disconnector
	end

	table.insert(self._disconnectors, disconnector)
	return disconnector
end

-- > // Func : Disconnect All \\ < --

function ListenerGroup:DisconnectAll()
	for _, disconnector in self._disconnectors do
		disconnector()
	end

	table.clear(self._disconnectors)
end

-- > // Func : Destroy \\ < --

function ListenerGroup:Destroy()
	self:DisconnectAll()
	self._disconnected = true
end

return ListenerGroup
