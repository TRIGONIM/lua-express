local pathRegexp = require("express.utils").pathRegexp
local dprint     = require("express.utils").debugPrint
local urldecode  = require("express.utils").urldecode

-- Представляет собой слой маршрутизации
-- Слои создаются в:
-- - ROUTER_MT:use strict = false, end = false
-- - ROUTER_MT:route strict = self.strict, end = true
-- - ROUTE_MT:$method false, false
--- @class ExpressRouterLayer: ExpressRouterLayerBase
--- @overload fun(path: string, options?: table, fn: ExpressMiddleware): ExpressRouterLayer
local LAYER_MT = setmetatable({}, {
	__call = function(self, path, options, fn)
		local opts = options or {}

		local pattern, keys = pathRegexp(path, opts.strict, opts["end"])

		local inf = debug.getinfo(fn, "S")
		local infstr = inf.short_src .. ":" .. inf.linedefined

		dprint("new %s (pattern: %s, strict: %s, end: %s)", path, pattern, opts.strict or "no", opts["end"] or "no")

		local layer = {    --- @class ExpressRouterLayerBase
			handle = fn,   --- @type ExpressMiddleware
			name = infstr, --- @type string generated function name (path and line defined)
			params = nil,  --- @type table? /user/:id -> {id = value}
			path = nil,    --- @type string? /user/:id -> /user
			keys = keys,   --- @type string[] /user/:id -> {"id"}
			regexp = {     --- @type table fields: {pattern, fast_star, fast_slash}
				-- pathRegexp(path, self.keys or {}, opts) -- #todo lua patterns, self implementation
				pattern = pattern, -- ^/([%w_]+)/bar/([%w_]+)(.*)$
				fast_star  = path == "*",
				fast_slash = path == "/" and opts["end"] == false,
			},
		}

		return setmetatable(layer, self)
	end
})
LAYER_MT.__index = LAYER_MT

-- Handle the error for the layer.
function LAYER_MT:handle_error(err, req, res, next)
	local fn = self.handle
	if debug.getinfo(fn, "Su").nparams ~= 4 then
		-- not a standard error handler
		return next(err)
	end

	local ok, er = pcall(fn, err, req, res, next)
	if not ok then next(er) end
end

-- Handle the request for the layer.
function LAYER_MT:handle_request(req, res, next)
	local fn = self.handle
	if debug.getinfo(fn, "Su").nparams > 3 then
		-- not a standard error handler
		return next()
	end

	local ok, err = pcall(fn, req, res, next)
	if not ok then next(err) end -- если ошибка в app:get() хендлере, то не останавливаемся, а идем к следующему, передавая ошибку дальше
end

-- Check if this route matches `path`, if so populate `.params`.
function LAYER_MT:match(path)
	local match = {}

	if path then
		if self.regexp.fast_slash then -- / and not opts.end
			self.params = {}
			self.path = ""
			return true
		end

		if self.regexp.fast_star then -- *
			self.params = {[0] = urldecode(path)}
			self.path = path
			return true
		end

		match = { path:match( self.regexp.pattern ) }
	end

	if not match[1] then
		self.params = nil
		self.path = nil
		return false
	end

	if path:sub(match[1]:len() + 1):len() > 0 then -- если строка была /birds/about, то надо выбрать /birds, а не /birds/. Это костыль для positive lookahead в js (?=\/|$)
		match[1] = match[1]:match("^(.-)/?$") -- убирает trailing slash в конце (если есть)
	end

	self.params = {}
	self.path = match[1] -- вернет /birds для /birds/about, если роут /birds (regexp.pattern == "^/birds")
	dprint("In layer:match('%s') self.path = '%s'", path, self.path) -- /birds/about > /birds

	local params = self.params

	for i, key in ipairs(self.keys) do
		-- Насчет i + 1:
		-- Если в роуте есть :param (#self.keys > 0), то match[1] будет весь путь, а match[2+] – группы (сами параметры)
		params[key] = urldecode( match[i + 1] ) -- %d0%b1%d0%bb%d0%b0%d0%b1%d0%bb%d0%b0%d0%b1%d0%bb%d0%b0 > блаблабла
	end

	return true
end

return LAYER_MT
