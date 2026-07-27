--[[
				OwlReplica - Main
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local RunService = game:GetService("RunService")
local OwlReplica

-- > // Func : Start \\ < --

if RunService:IsServer() then
    OwlReplica = require(script.Server)
else
    OwlReplica = require(script.Client)
end

(OwlReplica :: any).ListenerGroup = require(script.ListenerGroup)

return OwlReplica