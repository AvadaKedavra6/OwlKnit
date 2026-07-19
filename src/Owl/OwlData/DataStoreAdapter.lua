--[[
				Owl - DataStore Adapter
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local Promise = require(script.Parent.Parent.Parent.Libs.Promise)
local DataStoreService = game:GetService("DataStoreService")
local DataStore2 = require(script.Parent.Parent.Parent.Libs.DataStore2)

--

local OwlShared = require(script.Parent.Parent.OwlShared)
local Log = OwlShared.Logger("Data/DataStore2")

--

local LockExpiry = 60
local _LockKey = "_owlLock"
local VersionKey = "_version"
local MaxRetries = 3
local RetryDelay = 2

--

local Adapter = {}
Adapter.__index = Adapter

-- > // Func : New \\ < --

function Adapter.new(storeName: string, defaultData: {[string]: any}, migrations: {[number]: (data: {[string]: any}) -> ()}?)
	local self = setmetatable({}, Adapter)

	self._storeName = storeName
	self._default = defaultData
	self._migrations = migrations or {}
	self._sessions = {}

	local ok, lockStore = pcall(function()
		return DataStoreService:GetDataStore(storeName .. "_Locks")
	end)
	
	self._lockStore = ok and lockStore or nil

	return self
end

-- > // Func : Deep Copy \\ < --

local function deepCopy(t: {[any]: any}): {[any]: any}
	if type(t) ~= "table" then return t end
	local copy = {}
	
	for k, v in pairs(t) do
		copy[k] = deepCopy(v)
	end
	
	return copy
end

-- > // Func : Merge Defaults \\ < --

local function mergeDefaults(data: {[string]: any}, defaults: {[string]: any}): {[string]: any}
	for k, v in pairs(defaults) do
		if data[k] == nil then
			if type(v) == "table" then
				data[k] = deepCopy(v)
			else
				data[k] = v
			end
		end
	end
	
	return data
end

-- > // Func : Apply Migrations \\ < --

function Adapter:_applyMigrations(data: {[string]: any})
	local currentVersion = data[VersionKey] or 0
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

	data[VersionKey] = maxVersion
end

-- > // Func : Acquire Lock \\ < --

function Adapter:_acquireLock(userId: number): boolean
	if not self._lockStore then return true end

	local key = tostring(userId)
	local jobId = game.JobId
	local now = os.time()
	local acquired = false

	local ok, err = pcall(function()
		self._lockStore:UpdateAsync(key, function(existing)
			if not existing then
				acquired = true
				return { jobId = jobId, timestamp = now }
			end

			local isExpired = (now - (existing.timestamp or 0)) > LockExpiry
			local isOurs = existing.jobId == jobId

			if isExpired or isOurs then
				acquired = true
				return { jobId = jobId, timestamp = now }
			end

			return nil
		end)
	end)

	if not ok then
		Log.warn("Lock acquisition failed for userId %d: %s", userId, tostring(err))
		return false
	end

	return acquired
end

-- > // Func : Release Lock \\ < --

function Adapter:_releaseLock(userId: number)
	if not self._lockStore then return end
	local key = tostring(userId)
	
	pcall(function()
		self._lockStore:RemoveAsync(key)
	end)
end

-- > // Func : Save Data \\ < --

function Adapter:_saveData(userId: number)
	local session = self._sessions[userId]
	if not session then return end

	local ok, err = pcall(function()
		session.store:Set(session.data)
	end)

	if not ok then
		Log.warn("Save failed for userId %d: %s", userId, tostring(err))
		error(err)
	end
end

-- > // Func : Load Data \\ < --

function Adapter:Load(plr: Player): any
	return Promise.new(function(resolve, reject)
		local userId = plr.UserId
		local lockAcquired = false
		
		for attempt = 1, MaxRetries do
			lockAcquired = self:_acquireLock(userId)
			if lockAcquired then break end

			Log.warn("Lock not available for %s (attempt %d/%d), retrying...", plr.Name, attempt, MaxRetries)
			task.wait(RetryDelay)
		end

		if not lockAcquired then
			reject(("[Owl - Data] Could not acquire session lock for %s after %d attempts."):format(plr.Name, MaxRetries))
			return
		end

		if plr.Parent == nil then
			self:_releaseLock(userId)
			reject("Player left during lock acquisition.")
			return
		end

		local store = DataStore2(self._storeName, plr)
		local data = nil

		local loadOk, loadErr = pcall(function()
			data = store:GetTable(deepCopy(self._default))
		end)

		if not loadOk then
			self:_releaseLock(userId)
			reject(("[Owl - Data] DataStore2 load failed for %s: %s"):format(plr.Name, tostring(loadErr)))
			return
		end

		mergeDefaults(data, self._default)
		self:_applyMigrations(data)

		self._sessions[userId] = {
			store = store,
			data = data,
			jobId = game.JobId,
		}

		Log.info("Profile loaded for %s (v%s).", plr.Name, tostring(data[VersionKey] or 0))

		resolve({
			data = data,
			
			onSave = function()
				self:_saveData(userId)
			end,
			
			onRelease = function()
				local session = self._sessions[userId]
				
				if session then
					pcall(function() self:_saveData(userId) end)
					self:_releaseLock(userId)
					self._sessions[userId] = nil
				end
			end,
		})
	end)
end

-- > // Func : Save All \\ < --

function Adapter:SaveAll()
	for userId in pairs(self._sessions) do
		local ok, err = pcall(function()
			self:_saveData(userId)
		end)
		
		if not ok then
			Log.warn("SaveAll failed for userId %d: %s", userId, tostring(err))
		end
	end
end

return Adapter