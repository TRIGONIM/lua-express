-- Портировано отсюда (только функция path.resolve):
-- https://github.com/jinder/path/blob/master/path.js
-- Если нужны будут другие функции, то выносить наверное в lua-express-middlewares

local string_split = require("express.utils").string_split

-- resolves . and .. elements in a path array with directory names there
-- must be no slashes or device names (c:\) in the array
-- (so also no leading and trailing slashes - it does not distinguish
-- relative and absolute paths)
local normalizeArray = function(parts, allowAboveRoot)
	local res = {}
	for i = 1, #parts do
		local p = parts[i]

		-- ignore empty parts
		if not p or p == "." then
			goto continue
		end

		if p == ".." then
			if #res > 0 and res[#res] ~= ".." then
				table.remove(res)
			elseif allowAboveRoot then
				table.insert(res, "..")
			end
		else
			table.insert(res, p)
		end

		::continue::
	end

	return res
end

-- path.normalize(path)
-- posix version
local normalize = function(path)
	local isAbsolute = string.sub(path, 1, 1) == "/"
	local trailingSlash = string.sub(path, -1) == "/"

	-- Normalize the path
	local parts = string_split(path, "/")
	local normalizedParts = normalizeArray(parts, not isAbsolute)
	local normalizedPath = table.concat(normalizedParts, "/")

	if not normalizedPath and not isAbsolute then
		normalizedPath = "."
	end
	if normalizedPath and trailingSlash then
		normalizedPath = normalizedPath .. "/"
	end

	return (isAbsolute and "/" or "") .. normalizedPath
end


-- #todo full() realized for posix only</br>
-- returns file directory and filename without trailing slashes</br>
-- http://lua-users.org/lists/lua-l/2020-01/msg00345.html</br>
-- also related: https://stackoverflow.com/a/44527718</br>
-- `return os.getenv("PWD") or io.popen("pwd"):read("*l")`
--- @param relative_path string|number path or level. 1 is for local file
--- @return string, string
local function full(relative_path)
	local iLevel = type(relative_path) == "number" and relative_path
	local fullpath = iLevel and debug.getinfo(iLevel, "S").source:sub(2) or relative_path
	fullpath = io.popen("realpath '" .. fullpath .. "'", "r"):read("a")
	fullpath = fullpath:gsub("[\n\r]*$","")

	local dirname, filename = fullpath:match("^(.*)/([^/]-)$")
	dirname = dirname or ""
	filename = filename or fullpath

	return dirname, filename
end
-- print( "full()", full(1) )

-- path.resolve([from ...], to)
-- posix version
local function resolve(...)
	local resolvedPath = ""
	local resolvedAbsolute = false

	for i = select("#", ...), 0, -1 do
		local path = (i >= 1) and select(i, ...) or full( arg[0] )

		-- Skip empty and invalid entries
		if type(path) ~= "string" then
			error("Arguments to path.resolve must be strings")
		elseif not path then
			goto continue
		end

		resolvedPath = path .. "/" .. resolvedPath
		resolvedAbsolute = path:sub(1, 1) == "/"

		::continue::
	end

	-- At this point the path should be resolved to a full absolute path, but
	-- handle relative paths to be safe (might happen when full() fails)

	-- Normalize the path
	resolvedPath = table.concat(
		normalizeArray(string_split(resolvedPath, "/")),
		"/"
	) or "."

	return (resolvedAbsolute and "/" or "") .. resolvedPath
end

-- posix version
local function join(...)
	local path = ""
	for i = 1, select("#", ...) do
		local segment = select(i, ...)
		if type(segment) ~= "string" then
			error("Arguments to path.join must be strings")
		end
		if segment ~= "" then
			if path == "" then
				path = segment
			else
				path = path .. "/" .. segment
			end
		end
	end
	return normalize(path)
end

local path = {}
path.resolve = resolve
path.full = full
path.normalize = normalize
path.join = join

return path
