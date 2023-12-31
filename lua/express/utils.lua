local pattern_escape_replacements = {
	["("] = "%(",
	[")"] = "%)",
	["."] = "%.",
	["%"] = "%%",
	["+"] = "%+",
	["-"] = "%-",
	-- ["*"] = "%*",
	["?"] = "%?",
	["["] = "%[",
	["]"] = "%]",
	["^"] = "%^",
	["$"] = "%$",
	["\0"] = "%z"
}

local pattern_safe = function( str )
	return ( string.gsub( str, ".", pattern_escape_replacements ) )
end

-- https://github.com/pillarjs/path-to-regexp
local function pathRegexp(path, strict, ending)
	local keys = {}

	-- Удаляем символ / в начале, если strict не установлен
	if not strict then path = path:gsub("^/", "") end

	path = pattern_safe(path)

	-- path = path:gsub("%.", "%%.") -- заменяем точку на %.
	-- path = path:gsub("%-", "%%-")
	-- #todo "^ $ ( ) % . [ ] * + - ?", https://github.com/Facepunch/garrysmod/blob/e189f14c088298ca800136fcfcfaf5d8535b6648/garrysmod/lua/includes/extensions/string.lua#L58-L76
	-- только учесть, что "*" должна поддерживаться

	-- Заменяем :param на соответствующий паттерн
	path = path:gsub("(/?)%:([^/]+)", function(slash, key)
		keys[#keys + 1] = key
		-- Генерируем паттерн для параметра
		return slash .. "([^/]+)"
	end)

	-- /test/:foo/:bar создаст ^/test/([^/]+)/([^/]+)/?$
	-- в итоге match вернет параметры вместо пути, а нужен сам путь
	-- PRINT{ string.match("123", "((1)(2(3)))") } -- 123 1 23 3 (общая группа, вторая, третья, ...)
	if #keys > 0 then
		path = "(/" .. path .. "/?)"
	else
		path = "/" .. path .. "/?"
	end


	-- Экранируем символы, которые могут быть интерпретированы как регулярные выражения
	-- path = path:gsub("([%(%)%.%[%]%*%+%-%?%^%$%%])", "%%%1")
	-- path = path:gsub('([/%.])', '\\%1')

	-- Добавляем начало и, если нужно, конец регулярного выражения
	path = "^" .. path .. (ending and "$" or "")
	path = path:gsub("%*", "(.*)")

	-- Возвращаем регулярное выражение
	return path, keys
end

-- local pattern, keys = pathRegexp("/users/:id/:action*", false, true)
-- PRINT({pattern = pattern, keys = keys}) -- Выведет "^/users/([%w_]+)/([%w_]+)(.*)$"
-- PRINT(string.match("/users/123/create?foo=bar", pattern)) -- "123", "create", "?foo=bar"

local function getPathname(full_path)
	if full_path == "/" then return "/" end
	local pathname = full_path:match("^(/[^?&#]+)") -- /f0o/%d0%b1/_Bar/?a=b&c=d > /f0o/%d0%b1/_Bar/
	return pathname --:match("^(.-)/?$") -- убирает trailing slash в конце (если есть)
end


local glob_ok, globals = pcall(require, "gmod.globals")
if not glob_ok then
	globals = {}
	function globals.Color(r, g, b) return "" end
	function globals.MsgC(...) io.write(...) end
end

local Color, MsgC = globals.Color, globals.MsgC

local COL_EXPRESS  = Color(255, 0, 255)
local COL_FILENAME = Color(255, 255, 0)
local COL_CURLINE  = Color(0, 255, 255)
local COL_FUNCNAME = Color(0, 255, 0)
local COL_MSG      = Color(255, 255, 255)

local debug_enabled = false
local function debugPrint(...)
	if not debug_enabled then return end

	local inf = debug.getinfo(2, "Snl")
	local curline = inf.currentline -- [l] called from line num
	local name = inf.name or "" -- [n] function name from where called
	local source = inf.source -- [S] полный путь к файлу, с которого вызвана функция
	-- if source:sub(1, 1) == "@" then source = source:sub(2) end -- убираем @ из начала строки
	local filename = source:match("([^/]+)$")

	-- "[express] {{filename}}:{{curline}} {{name}}: {{msg}}"
	local f = string.format

	local args = {...}
	local msg = f(args[1], unpack(args, 2))

	MsgC(COL_EXPRESS, "[express] ", COL_FILENAME, f("%10s", filename), COL_CURLINE, ":", f("%-3s", curline), COL_FUNCNAME, " ", f("%10s", name), COL_MSG, ": ", msg, "\n")
	-- print("[express]", string.format(args[1], unpack(args, 2)))
end

local function string_URLDecode(str)
	if str == "" then return str end
	str = str:gsub('+', ' ')
	return str:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
end

-- require("express.utils").urldecode
return {
	pathRegexp  = pathRegexp,
	getPathname = getPathname,
	debugPrint  = debugPrint,
	urldecode   = string_URLDecode,
}
