<<<<<<< HEAD
local RepStorage = game:GetService("ReplicatedStorage")
local Owl = require(RepStorage.OwlKnit.Owl)
local EconomyAddon = {}
 
EconomyAddon.Name = "EconomyAddon"
EconomyAddon.Version = "1.0.0"
EconomyAddon.Author = "Morax"
EconomyAddon.Description = ""
EconomyAddon.OwlVersion = ">=1.1.0"
EconomyAddon.Dependencies = {} -- > // No other addons required for works
EconomyAddon.OptionalDependencies = {"AnalyticsAddon"} -- > // Can depends of an another addon like "Analytics" but only if he existing, if not then he just ignores it
EconomyAddon.Hooks = {}
 
function EconomyAddon.Hooks.Init(self: typeof(EconomyAddon), owl: any)
end
 
function EconomyAddon.Hooks.OnFrameworkStarted(self: typeof(EconomyAddon))
end
 
function EconomyAddon.Hooks.OnServiceRegisted(self: typeof(EconomyAddon))
end
 
Owl.RegisterAddon(EconomyAddon)
=======
local RepStorage = game:GetService("ReplicatedStorage")
local Owl = require(RepStorage.OwlKnit.Owl)
local EconomyAddon = {}
 
EconomyAddon.Name = "EconomyAddon"
EconomyAddon.Version = "1.0.0"
EconomyAddon.Author = "Morax"
EconomyAddon.Description = ""
EconomyAddon.OwlVersion = ">=1.1.0"
EconomyAddon.Dependencies = {} -- > // No other addons required for works
EconomyAddon.OptionalDependencies = {"AnalyticsAddon"} -- > // Can depends of an another addon like "Analytics" but only if he existing, if not then he just ignores it
EconomyAddon.Hooks = {}
 
function EconomyAddon.Hooks.Init(self: typeof(EconomyAddon), owl: any)
end
 
function EconomyAddon.Hooks.OnFrameworkStarted(self: typeof(EconomyAddon))
end
 
function EconomyAddon.Hooks.OnServiceRegisted(self: typeof(EconomyAddon))
end
 
Owl.RegisterAddon(EconomyAddon)
>>>>>>> 943ce95523cb02414b59b715d629c1f31293040b
return EconomyAddon