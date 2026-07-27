--[[
				OwlReplica - PathUtils
				This is a Replica rewrite
				Made with <3 by Dev_Abrahel | dc: ._morax6_.
--]]

-- > // Variables \\ < --

local Types = require(script.Parent.Types)
type Path = Types.Path

--

local PathUtils = {}

-- > // Func : Resolve \\ < --

function PathUtils.Resolve(root: {[any]: any}, path: Path): (({[any]: any})?, (string | number)?)
	if #path == 0 then
		return nil, nil
	end

	local current = root
	for i = 1, #path - 1 do
		local key = path[i]
		local next_value = current[key]

		if type(next_value) ~= "table" then
			warn(`[OwlReplica] Invalid path, "{tostring(key)}" is not a table.`)
			return nil, nil
		end

		current = next_value
	end

	return current, path[#path]
end

-- > // Func : Get \\ < --

function PathUtils.Get(root: {[any]: any}, path: Path): any
	if #path == 0 then
		return root
	end

	local parent, key = PathUtils.Resolve(root, path)
	if parent == nil then
		return nil
	end

	return parent[key :: any]
end

-- > // Func : Set \\ < --

function PathUtils.Set(root: {[any]: any}, path: Path, value: any): any
	local parent, key = PathUtils.Resolve(root, path)

	if parent == nil then
		return nil
	end

	local old_value = parent[key :: any]
	parent[key :: any] = value

	return old_value
end

-- > // Funcs : Arrays \\ < --

function PathUtils.ArrayInsert(root: {[any]: any}, path: Path, value: any): number
	local array = PathUtils.Get(root, path)
	assert(type(array) == "table", `[OwlReplica] ArrayInsert: path is not a table.`)

	local new_index = #array + 1
	array[new_index] = value

	return new_index
end

--

function PathUtils.ArraySet(root: {[any]: any}, path: Path, index: number, value: any): any
	local array = PathUtils.Get(root, path)
	assert(type(array) == "table", `[OwlReplica] ArraySet: path is not a table.`)

	local old_value = array[index]
	array[index] = value

	return old_value
end

--

function PathUtils.ArrayRemove(root: {[any]: any}, path: Path, index: number): any
	local array = PathUtils.Get(root, path)
	assert(type(array) == "table", `[OwlReplica] ArrayRemove: path is not a table.`)

	local removed = table.remove(array, index)
	return removed
end

-- > // Func : Equals \\ < --

function PathUtils.Equals(a: Path, b: Path): boolean
	if #a ~= #b then
		return false
	end

	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

-- > // Func : Starts With \\ < --

function PathUtils.StartsWith(path: Path, prefix: Path): boolean
	if #prefix > #path then
		return false
	end

	for i = 1, #prefix do
		if path[i] ~= prefix[i] then
			return false
		end
	end

	return true
end

-- > // Func : To Key \\ < --

function PathUtils.ToKey(path: Path): string
	local parts = table.create(#path)

	for i, v in ipairs(path) do
		parts[i] = tostring(v)
	end

	return table.concat(parts, "\0")
end

-- > // Func : Prefix Keys \\ < --

function PathUtils.PrefixKeys(path: Path): {string}
	local keys = table.create(#path)
	local acc = ""

	for i, v in ipairs(path) do
		acc = if i == 1 then tostring(v) else acc .. "\0" .. tostring(v)
		keys[i] = acc
	end

	return keys
end

return PathUtils