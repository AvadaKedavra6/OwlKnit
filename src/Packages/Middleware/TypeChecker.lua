--[[
				Owl - TypeChecker
				Made with <3 by Dev_Abrahel | dc: astaroth9._
--]]

-- > // Variables \\ < --

local PrimitiveTypes = {
	["string"] = true,
	["number"] = true,
	["boolean"] = true,
	["table"] = true,
	["function"] = true,
	["thread"] = true,
	["nil"] = true,
	["any"] = true,
	["Vector2"] = true,
	["Vector3"] = true,
	["CFrame"] = true,
	["Color3"] = true,
	["BrickColor"] = true,
	["UDim"] = true,
	["UDim2"] = true,
	["Rect"] = true,
	["Region3"] = true,
	["Ray"] = true,
	["Enum"] = true,
	["EnumItem"] = true,
	["TweenInfo"] = true,
	["NumberRange"] = true,
	["NumberSequence"] = true,
	["ColorSequence"] = true,
	["Instance"] = true,
}

--

local TypeChecker = {}

-- > // Types \\ < --

export type ValidationResult = {
	ok: boolean,
	err: string?,
}

--

export type CheckFn = (value: any) -> ValidationResult

-- > // Func : Describe \\ < --

local function describe(value: any): string
	local t = typeof(value)
	
	if t == "Instance" then
		return value.ClassName
	end
	
	if t == "nil" then
		return "nil"
	end
	
	return t
end

-- > // Func : Create Checker \\ < --

local createCheck: (schema: any) -> CheckFn

createCheck = function(schema: any): CheckFn
	if type(schema) == "string" then
		local isOptional = schema:find("%?") ~= nil or schema:find("%f[%a]nil%f[%A]") ~= nil
		local unionTypes: {string} = {}
		
		for token in schema:gmatch("([^|%s%?]+)") do
			if token ~= "nil" then
				table.insert(unionTypes, token)
			end
		end

		return function(value: any): ValidationResult
			if value == nil then
				if isOptional then
					return { ok = true }
				end
				
				return { ok = false, err = ("Expected %s, got nil"):format(schema) }
			end

			if #unionTypes == 1 and unionTypes[1] == "any" then
				return { ok = true }
			end

			local valType  = typeof(value)
			local valClass = valType == "Instance" and value.ClassName or nil

			for _, t in ipairs(unionTypes) do
				if t == "any" then
					return { ok = true }
				end

				if PrimitiveTypes[t] then
					if valType == t then
						return { ok = true }
					end

					if t == "Instance" and valType == "Instance" then
						return { ok = true }
					end
				end


				if valType == "Instance" then
					local ok, result = pcall(function()
						return value:IsA(t)
					end)
					
					if ok and result then
						return { ok = true }
					end
				end
			end

			return {
				ok  = false,
				err = ("Expected %s, got %s"):format(schema, valClass or valType),
			}
		end
	elseif type(schema) == "table" then
		if schema.__array ~= nil then
			local elementCheck = createCheck(schema.__array)

			return function(value: any): ValidationResult
				if type(value) ~= "table" then
					return { ok = false, err = ("Expected array (table), got %s"):format(typeof(value)) }
				end

				for i, element in ipairs(value) do
					local result = elementCheck(element)
					
					if not result.ok then
						return {
							ok  = false,
							err = ("[%d]: %s"):format(i, result.err),
						}
					end
				end

				return { ok = true }
			end
		end

		local fieldChecks: {[string]: CheckFn} = {}
		for key, subSchema in pairs(schema) do
			fieldChecks[key] = createCheck(subSchema)
		end

		return function(value: any): ValidationResult
			if type(value) ~= "table" then
				return { ok = false, err = ("Expected table, got %s"):format(typeof(value)) }
			end

			for key, check in pairs(fieldChecks) do
				local result = check(value[key])
				
				if not result.ok then
					return {
						ok  = false,
						err = (".%s: %s"):format(tostring(key), result.err),
					}
				end
			end

			return { ok = true }
		end
	else
		return function(value: any): ValidationResult
			if value == schema then
				return { ok = true }
			end
			
			return {
				ok  = false,
				err = ("Expected literal %s, got %s"):format(tostring(schema), describe(value)),
			}
		end
	end
end

-- > // Func : Args \\ < --

function TypeChecker.args(...: any): (plr: Player, args: {any}) -> (boolean, ...any)
	local schemas = {...}
	local compiled: {CheckFn} = {}

	for _, schema in ipairs(schemas) do
		table.insert(compiled, createCheck(schema))
	end

	return function(plr: Player, args: {any}): (boolean, ...any)
		for i, check in ipairs(compiled) do
			local value  = args[i]
			local result = check(value)

			if not result.ok then
				warn(("[Owl - TypeChecker] Inbound validation failed for %s, Arg[%d]: %s"):format(
					plr.Name, i, result.err or "unknown error"
					))
				return false
			end
		end

		return true
	end
end

-- > // Func : Returns \\ < --

function TypeChecker.returns(...: any): (plr: Player, args: {any}) -> (boolean, ...any)
	local schemas = {...}
	local compiled: {CheckFn} = {}

	for _, schema in ipairs(schemas) do
		table.insert(compiled, createCheck(schema))
	end

	return function(plr: Player, args: {any}): (boolean, ...any)
		for i, check in ipairs(compiled) do
			local value  = args[i]
			local result = check(value)

			if not result.ok then
				warn(("[Owl - TypeChecker] Outbound validation failed for %s, Return[%d]: %s"):format(
					plr.Name, i, result.err or "unknown error"
					))
				return false
			end
		end

		return true
	end
end

-- > // Func : Validate \\ < --

function TypeChecker.validate(value: any, schema: any): (boolean, string?)
	local result = createCheck(schema)(value)
	return result.ok, result.err
end

-- > // Func : Compile \\ < --

function TypeChecker.compile(schema: any): (value: any) -> (boolean, string?)
	local check = createCheck(schema)
	
	return function(value: any): (boolean, string?)
		local result = check(value)
		return result.ok, result.err
	end
end

return TypeChecker