-- Implementation of
-- https://github.com/pillarjs/finalhandler/blob/master/index.js#L275

local dprint = require("express.utils").debugPrint

-- https://github.com/python/cpython/blob/3.10/Lib/html/__init__.py#L12
-- #todo может, можно улучшить через https://github.com/component/escape-html/blob/master/index.js
local escape_html = function(str)
	return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("'", "&#39;"):gsub("\"", "&quot;") -- :gsub("'", "&#x27;")
end

local function string_URLEncode(str)
	return string.gsub(string.gsub(str, "\n", "\r\n"), "([^%w.])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

-- https://github.com/pillarjs/finalhandler/blob/5ceb3e3e2482404cb71e9810bd10a422fe748f20/index.js#L43
local createHtmlDocument = function(message)
	local body = escape_html(message):gsub("\n", "<br>"):gsub("  ", " &nbsp;")

	return "<!DOCTYPE html>\n" ..
    "<html lang='en'>\n" ..
    "<head>\n" ..
    "<meta charset='utf-8'>\n" ..
    "<title>Error</title>\n" ..
    "</head>\n" ..
    "<body>\n" ..
    "<pre>" .. body .. "</pre>\n" ..
    "</body>\n" ..
    "</html>\n"
end

local send = function(req, res, status, headers, msg)
	local body = createHtmlDocument(msg)

	if status then
		res:setstatus(status)
	end

	res:set("Content-Encoding", nil)
	res:set("Content-Language", nil)
	res:set("Content-Range", nil)

	for name, val in pairs(headers or {}) do
		res:set(name, val) --:write(msg)
	end

	res:set("Content-Security-Policy", "default-src 'none'")
	res:set("X-Content-Type-Options", "nosniff")
	res:set("Content-Type", "text/html; charset=utf-8")
	res:set("Content-Length", body:len()) -- сейчас ни на что не влияет. Оверрайдится тут: https://github.com/EvandroLG/pegasus.lua/blob/2a3f4671f45f5111c14793920771f96b819099ab/src/pegasus/response.lua#L180C29-L180C35

	if req.method == "HEAD" then
		res:sendOnlyHeaders() -- https://github.com/EvandroLG/pegasus.lua/blob/2a3f4671f45f5111c14793920771f96b819099ab/src/pegasus/response.lua#L165C19-L165C36
		return
	end

	res:send(body)
end

local getErrorStatusCode = function(err)
	-- if type(err) ~= "table" then return end
	if type(err.status) == "number" and err.status >= 400 and err.status < 600 then
		return err.status
	end
end

-- #todo добавить реализацию https://github.com/pillarjs/finalhandler/blob/master/index.js#L86
local finalhandler = function(req, res, options)
	local opts = options or {}
	local env = opts.env or os.getenv("LUA_ENV") or "development"
	local onerror = opts.onerror

	return function(err)
		local headers, msg, status -- #todo headers не используется из-за упрощения функции

		-- res._headersSended: https://github.com/EvandroLG/pegasus.lua/blob/2a3f4671f45f5111c14793920771f96b819099ab/src/pegasus/response.lua#L89C9-L89C24
		if not err and res._headersSended then print("cannot 404 after headers sent") return end

		if err and type(err) == "table" then
			status = getErrorStatusCode(err)
			if status then
				headers = err.headers
			end

			local mes = err.message or "Internal Server Error"
			local trace = err.stack or debug.traceback()
			trace = mes .. "\n\n" .. trace

			msg = env == "production" and ("Error " .. status) or trace

		elseif err then
			status = 500
			msg = env == "production"
				and "Internal Server Error"
				or debug.traceback(err)
		else
			status = 404
			msg = "Cannot " .. req.method .. " " .. string_URLEncode(req.url)
		end

		dprint("default %s", status)

		if err and onerror then
			onerror(err, req, res)
		end

		-- 404, 500, если не было кастомного error handler'a
		send(req, res, status, headers, msg)
	end
end

return finalhandler
