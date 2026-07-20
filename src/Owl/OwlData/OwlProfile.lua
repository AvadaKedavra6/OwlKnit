--[[
				Owl - Profile
				This is a Knit rewrited for be more modern and friendly
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local Promise = require(script.Parent.Parent.Parent.Libs.Promise)
local Signal = require(script.Parent.Parent.Parent.Libs.Signal)
local Trove = require(script.Parent.Parent.Parent.Libs.Trove)

--

local OwlShared = require(script.Parent.Parent.OwlShared)
local Log = OwlShared.Logger("Data/Profile")

--

local OwlProfile = {}
OwlProfile.__index = OwlProfile

-- > // Func : New \\ < --

function OwlProfile.new(plr: Player, data: {[string]: any}, onSave: () -> (), onRelease: () -> ())
	local self = setmetatable({}, OwlProfile)
	
	self._plr = plr
	self._data = data
	self._trove = Trove.new()
	self._onSave = onSave
	self._onRelease = onRelease
	self._loaded = true
	self._released = false
	
	self._observers = {}
	self.Saved = self._trove:Add(Signal.new())
	self.Released = self._trove:Add(Signal.new())
	self.SaveFailed = self._trove:Add(Signal.new())
	
	return self
end

-- > // Func : Notify Observer \\ < --

function OwlProfile:_notifyObservers(key: string, new: any, old: any)
	local sig = self._observers[key]
	local wildcard = self._observers["*"]
	
	if sig then
		sig:Fire(new, old)
	end

	if wildcard then
		wildcard:Fire(key, new, old)
	end
end

-- > // Funcs : IsLoaded/IsReleased \\ < --

function OwlProfile:IsLoaded(): boolean
	return self._loaded
end

--

function OwlProfile:IsReleased(): boolean
	return self._released
end

-- > // Func : Get \\ < --

function OwlProfile:Get(key: string): any
	if self._released then
		Log.warn("Tried to Get(%q) on a released profile for %s.", key, self._plr.Name)
		return nil
	end

	if key:find("%.") then
		local parts  = key:split(".")
		local cursor = self._data
		
		for _, part in ipairs(parts) do
			if type(cursor) ~= "table" then 
				return nil 
			end
			
			cursor = cursor[part]
		end
		
		return cursor
	end

	return self._data[key]
end

-- > // Func : Get All \\ < --

function OwlProfile:GetAll(): {[string]: any}
	if self._released then return {} end
	local copy = {}
	
	for k, v in pairs(self._data) do
		copy[k] = v
	end
	
	return copy
end

-- > // Func : Set \\ < --

function OwlProfile:Set(key: string, value: any)
	if self._released then
		Log.warn("Tried to Set(%q) on a released profile for %s.", key, self._plr.Name)
		return
	end

	if key:find("%.") then
		local parts  = key:split(".")
		local cursor = self._data
		
		for i = 1, #parts - 1 do
			local part = parts[i]
			
			if type(cursor[part]) ~= "table" then
				cursor[part] = {}
			end
			
			cursor = cursor[part]
		end
		
		local lastKey = parts[#parts]
		local old = cursor[lastKey]
		cursor[lastKey] = value
		
		self:_notifyObservers(key, value, old)
		return
	end

	local old = self._data[key]
	self._data[key] = value
	self:_notifyObservers(key, value, old)
end

-- > // Func : Update \\ < --

function OwlProfile:Update(key: string, fn: (old: any) -> any)
	if self._released then
		Log.warn("Tried to Update(%q) on a released profile for %s.", key, self._plr.Name)
		return
	end

	local old = self:Get(key)
	local new = fn(old)
	self:Set(key, new)
end

-- > // Funcs : Increment/Decrement \\ < --

function OwlProfile:Increment(key: string, amount: number?)
	amount = amount or 1
	local current = self:Get(key)
	
	assert(type(current) == "number", ("[Owl - Data] Increment: key %q is not a number (got %s)."):format(key, type(current)))
	self:Set(key, current + amount)
end

--

function OwlProfile:Decrement(key: string, amount: number?)
	amount = amount or 1
	local current = self:Get(key)
	
	assert(type(current) == "number", ("[Owl - Data] Decrement: key %q is not a number (got %s)."):format(key, type(current)))
	self:Set(key, current - amount)
end


-- > // Funcs : Append/Remove \\ < --

function OwlProfile:Append(key: string, value: any)
	local arr = self:Get(key)
	assert(type(arr) == "table", ("[Owl - Data] Append: key %q is not a table."):format(key))
	
	local new = {}
	
	for _, v in ipairs(arr) do 
		table.insert(new, v) 
	end
	
	table.insert(new, value)
	self:Set(key, new)
end

--

function OwlProfile:Remove(key: string, value: any)
	local arr = self:Get(key)
	assert(type(arr) == "table", ("[Owl - Data] Remove: key %q is not a table."):format(key))
	
	local new = {}
	
	for _, v in ipairs(arr) do
		if v ~= value then
			table.insert(new, v)
		end
	end
	
	self:Set(key, new)
end

-- > // Func : Observe \\ < --

function OwlProfile:Observe(key: string, fn: (new: any, old: any) -> ()): () -> ()
	if not self._observers[key] then
		self._observers[key] = Signal.new()
		self._trove:Add(self._observers[key])
	end

	local conn = self._observers[key]:Connect(fn)

	if key ~= "*" then
		local current = self:Get(key)
		task.defer(fn, current, nil)
	end

	return function()
		conn:Disconnect()
	end
end

-- > // Func : Save \\ < --

function OwlProfile:Save(): any
	if self._released then
		Log.warn("Tried to Save() on a released profile for %s.", self._plr.Name)
		return Promise.reject("Profile already released.")
	end

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(self._onSave)
		
		if ok then
			Log.info("Profile saved for %s.", self._plr.Name)
			self.Saved:Fire()
			resolve()
		else
			Log.warn("Save failed for %s: %s", self._plr.Name, tostring(err))
			self.SaveFailed:Fire(err)
			reject(err)
		end
	end)
end

-- > // Func : Release \\ < --

function OwlProfile:_release()
	if self._released then return end
	self._released = true
	self._loaded = false

	local ok, err = pcall(self._onRelease)
	
	if not ok then
		Log.warn("Release failed for %s: %s", self._plr.Name, tostring(err))
	end

	self.Released:Fire()
	self._trove:Destroy()

	for k in pairs(self._observers) do
		self._observers[k] = nil
	end
end

return OwlProfile