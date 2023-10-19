-- Implementation of
-- https://github.com/pillarjs/finalhandler/blob/master/index.js#L275

local dprint = require("express.utils").debugPrint

-- https://github.com/python/cpython/blob/3.10/Lib/html/__init__.py#L12
-- #todo может, можно улучшить через https://github.com/component/escape-html/blob/master/index.js
local escape_html = function(str)
	return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("'", "&#39;"):gsub("\"", "&quot;") -- :gsub("'", "&#x27;")
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

-- #todo добавить реализацию https://github.com/pillarjs/finalhandler/blob/master/index.js#L86
local finalhandler = function(req, res, options)
	local opts = options or {}
	-- local env = opts.env or os.getenv("LUA_ENV") or "development"
	local onerror = opts.onerror

	return function(err)
		local headers, msg, status = {}, "hello pegasus world!", nil -- #todo headers не используется из-за упрощения функции

		-- res._headersSended: https://github.com/EvandroLG/pegasus.lua/blob/2a3f4671f45f5111c14793920771f96b819099ab/src/pegasus/response.lua#L89C9-L89C24
		if not err and res._headersSended then dprint("cannot 404 after headers sent") return end

		-- unhandled error
		if err then -- #todo сильно упрощено, нужно доделать динамичность
			status = 500
			msg = "Error " .. tostring(err) -- не знаю нужен ли тут tostring
		else
			status = 404
			msg = "Cannot " .. req.method .. " " .. req.url
		end

		local send = function(req, res, status, headers, msg)
			local body = createHtmlDocument(msg)

			if status then
				res:setstatus(status)
			end

			res:set("Content-Encoding", nil)
			res:set("Content-Language", nil)
			res:set("Content-Range", nil)

			for name, val in pairs(headers) do
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

		if err and onerror then
			onerror(err, req, res)
		end

		-- 404, 500, если не было кастомного error handler'a
		send(req, res, status, headers, msg)
	end
end

return finalhandler
