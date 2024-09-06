-- https://github.com/pillarjs/path-to-regexp
-- В финальную регулярку не передаются параметры ?a=b&c=d
-- Для /files/:file(*) возвращается /^\/files\/(?:((.*)))\/?$/i
-- Для /files/:file*   возвращается /^\/files\/(?:([^\/]+?)((?:[\/].+?)?))\/?$/i
-- Заметки (второе без (*) в конце пути):
-- /users/:id/some/:action(*)
-- /^\/users\/(?:([^\/]+?))\/some\/(?:((.*)))\/?$/i
-- /^\/users\/(?:([^\/]+?))\/some\/(?:([^\/]+?))\/?$/i
local function regexpFromPath(path, strict, ending)
	local keys = {}
	-- path = pattern_safe(path) -- не знаю зачем добавлял. Больше мешало, чем помогало
	-- учесть, что "*" должна поддерживаться

	-- Заменяем :param на соответствующий паттерн
	path = path:gsub("(/?)%:([^/]+)", function(slash, key)
		local gsubed, changes = key:gsub("%(%*%)$", "")
		keys[#keys + 1] = gsubed
		return slash .. (changes > 0 and "(.*)" or "([^/]+)")
	end)

	path = path .. (strict and "/" or "/?")

	-- /test/:foo/:bar создаст ^/test/([^/]+)/([^/]+)/?$
	-- в итоге match вернет параметры вместо пути, а нужен сам путь
	-- PRINT{ string.match("123", "((1)(2(3)))") } -- 123 1 23 3 (общая группа, вторая, третья, ...)
	if #keys > 0 then path = "(" .. path .. ")" end

	-- Добавляем начало и, если нужно, конец регулярного выражения
	path = "^" .. path .. (ending and "$" or "")

	-- Возвращаем регулярное выражение
	return path, keys
end

-- local pattern, keys = regexpFromPath("/users/:id/some/:action(*)", false, true)
-- require("tlib").PRINT({pattern = pattern, keys = keys}) -- ^(/users/([^/]+)/some/(.*)/?)$
-- require("tlib").PRINT(string.match("/users/123/some/create?foo=bar", pattern)) -- $full_path, "123", "create?foo=bar"
-- require("tlib").PRINT(string.match("/users/123/some/create/post?foo=bar", pattern)) -- $full_path, "123", "create/post?foo=bar"

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

local function string_Split(str, char)
	local t = {}
	for s in string.gmatch(str, "([^" .. char .. "]+)") do
		t[#t + 1] = s
	end
	return t
end

-- https://github.com/expressjs/express/blob/2a980ad16052e53b398c9953fea50e3daa0b495c/lib/utils.js#L56
-- Только для res:sendFile сейчас. #todo поддержка windows (не сложно), а с ней path.lua тоже под Windows сделать
local function isAbsolute(path)
	return path:sub(1, 1) == "/"
end

-- require("express.utils").urldecode
return {
	pathRegexp   = regexpFromPath,
	getPathname  = getPathname,
	debugPrint   = debugPrint,
	urldecode    = string_URLDecode,
	isAbsolute   = isAbsolute,
	string_split = string_Split
}
