local router = require("express").Router()

-- The :param method will first try to get the value from req.params, then from req.body, then from req.query tables.
-- ℹ️ Open in browser /prefixed/route/param/blablabla
router:get("/param/:any", function(req, res)
	res:send("Hello from GET /prefixed/route/param/" .. req:param("any"))
end)

-- This requires lua-cjson module installed.
-- res:json() automatically sets the Content-Type header to application/json
-- ℹ️ Open in browser /prefixed/route/info
router:get("/info", function(req, res)
	-- https://github.com/TRIGONIM/lua-gmod-lib/blob/755db2abae6accdd41e67ca1a94eb650bf55f12e/lua/gmod/globals.lua#L167
	-- require("gmod.globals").PrintTable(req)

	res:json({
		body    = req.body or "not set", -- requires body-parser middleware (https://github.com/TRIGONIM/lua-express-middlewares)
		cookies = req.cookies or "not set", -- {["cookie-name"] = "cookie-value"} (https://github.com/TRIGONIM/lua-express-middlewares)
		headers = req.headers, -- {["lower-case-name"] = "value"}
		ip      = req:ip(), -- app:set("trust proxy", {"uniquelocal"}) implemented: https://expressjs.com/en/guide/behind-proxies.html
		query   = req.query, -- /info?query=string > {query = "string"}
		params  = req.params, -- /info/:param > {param = "value"}. Can be only empty table in this example
		method  = req.method, -- GET, POST, PUT, DELETE, etc
		url     = req.url, -- /info
		baseUrl = req.baseUrl, -- /prefixed/route
		originalUrl = req.originalUrl, -- /prefixed/route/info

		-- prepared to be sent to the client
		-- the pg_res field mapping to original pegasus response object:
		-- https://github.com/EvandroLG/pegasus.lua/blob/master/src/pegasus/response.lua
		response = {
			headers = res.pg_res._headers,
			status  = res.pg_res.status,
			headers_sent = res.pg_res._headersSended,
		}
	})
end)

-- This errors will be handled by the error handler in init.lua
-- ℹ️ Open in browser /prefixed/route/error
local i = 0
router:get("/error", function(_, _, next)
	i = i + 1

	if i == 1 then
		next("error text 1")
	elseif i == 2 then
		error("error text 2", 2)
	elseif i == 3 then
		next({
			message = "error text 3",
			status  = 403, -- custom response status
			stack   = debug.traceback(),
			headers = { -- additional headers
				["X-Some-Header"] = "foo bar",
			}
		})
	else
		i = 0
		print("string plus number" + 1) -- this will throw an error
	end
end)

return router
