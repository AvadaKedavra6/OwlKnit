--[[
				Owl - Profile Adapter
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local Promise = require(script.Parent.Parent.Parent.Libs.Promise)
local ProfileStore = require(script.Parent.Parent.Parent.Libs.ProfileStore)

--

local OwlShared = require(script.Parent.Parent.OwlShared)
local Log = OwlShared.Logger("Data/ProfileStore")

--

local Adapter = {}
Adapter.__index = Adapter

-- > // Func : New \\ < --

function Adapter.new(storeName: string, defaultData: {[string]: any}, migrations: {[number]:  (data: {[string]: any}) -> ()}?)
	local self = setmetatable({}, Adapter)
	
	self._storeName = storeName
	self._default = defaultData
	self._migrations = migrations or {}
	self._store = ProfileStore.New(storeName, defaultData)
	self._profiles = {}
	
	return self
end

-- > // Func : Apply Migration \\ < --

function Adapter:_applyMigrations(data: {[string]: any})
	local currentVersion = data._version or 0
	local maxVersion = 0
	
	for v in pairs(self._migrations) do
		if v > maxVersion then
			maxVersion = v
		end
	end
	
	if currentVersion >= maxVersion then return end
	Log.info("Migrating profile from v%d to v%d...", currentVersion, maxVersion)

	for v = currentVersion + 1, maxVersion do
		local fn = self._migrations[v]
		
		if type(fn) == "function" then
			local ok, err = pcall(fn, data)
			if not ok then
				Log.warn("Migration v%d failed: %s", v, tostring(err))
			else
				Log.info("Migration v%d applied.", v)
			end
		end
	end
	
	data._version = maxVersion
end

-- > // Func : Load Profile \\ < --

function Adapter:Load(plr: Player): any
	return Promise.new(function(resolve, reject)
		local profile = self._store:StartSessionAsync(tostring(plr.UserId), {
			Cancel = function()
				return plr.Parent == nil
			end,
		})

		if not profile then
			reject(("[Owl - Data] ProfileStore failed to load profile for %s (%d)."):format(plr.Name, plr.UserId))
			return
		end

		if plr.Parent == nil then
			profile:EndSession()
			reject("Player left during load.")
			return
		end

		self:_applyMigrations(profile.Data)
		self._profiles[plr.UserId] = profile
		Log.info("Profile loaded for %s (v%s).", plr.Name, tostring(profile.Data._version or 0))

		profile.OnSessionEnd:Connect(function()
			Log.warn("Session ended for %s, kicking.", plr.Name)
			self._profiles[plr.UserId] = nil
			if plr.Parent then
				plr:Kick("[Owl] Your session has been released, please reconnect.")
			end
		end)

		resolve({
			data = profile.Data,
			
			onSave = function()
				if self._profiles[plr.UserId] then
					-- > // No-op : ProfileStore auto-save
				end
			end,
			
			onRelease = function()
				local p = self._profiles[plr.UserId]
				
				if p then
					p:EndSession()
					self._profiles[plr.UserId] = nil
				end
			end,
		})
	end)
end

-- > // Func : Save All \\ < --

function Adapter:SaveAll()
	for userId, profile in pairs(self._profiles) do
		local ok, err = pcall(function()
			profile:Save()
		end)
		
		if not ok then
			Log.warn("SaveAll failed for userId %d: %s", userId, tostring(err))
		end
	end
end

return Adapter