local LAYER_MT = require("express.router.layer")
local methods  = require("express.misc.methods")

local dprint = require("express.utils").debugPrint

--- @class ExpressRouterLayer
--- @field method string

--- @class ExpressRouterRoute: ExpressRouterRouteBase
--- @overload fun(path: string): ExpressRouterRoute
local ROUTE_MT = setmetatable({}, {
	__call = function(self, path)
		dprint("new %s", path)

		local route = {   --- @class ExpressRouterRouteBase
			path = path,  --- @type string
			stack = {},   --- @type ExpressRouterLayer[]
			methods = {}, --- @type table<string, boolean> get = true etc.
		}
		return setmetatable(route, self)
	end
})
ROUTE_MT.__index = ROUTE_MT

-- Determine if the route handles a given method.
function ROUTE_MT:_handles_method(method)
	if self.methods._all then return true end

	local name = method:lower()
	return not not self.methods[name]
end

-- supported http methods (но сейчас просто апперкейс методы)
-- используется для OPTION запроса. Нз зачем
function ROUTE_MT:_options()
	local methods_upper = {}
	for me in pairs( self.methods ) do
		methods_upper[#methods_upper + 1] = me:upper()
	end
	return methods_upper
end

function ROUTE_MT:dispatch(req, res, done)
	local idx = 0
	local stack = self.stack
	local sync = 0

	if not stack[1] then return done() end

	local method = req.method:lower()

	req.route = self

	local function next(err)
		if err and err == "route"  then return done() end -- signal to exit route
		if err and err == "router" then return done(err) end

		-- #todo timer. Разобраться с setImmediate в JS
		if sync > 100 then print("ROUTE_MT:dispatch. There was setImmediate in original express") next(err) return end -- require("gmod.timer").Simple(0, function() next(err) end)
		sync = sync + 1
		idx  = idx + 1
		local layer = stack[idx]
		if not layer then return done(err) end

		if layer.method and layer.method ~= method then
			next(err)
		elseif err then
			layer:handle_error(err, req, res, next)
		else
			layer:handle_request(req, res, next)
		end

		sync = 0
	end

	next()
end

--- @param ... ExpressMiddleware
--- @return ExpressRouterRoute
function ROUTE_MT:all(...)
	local handles = {...}

	for _, handle in ipairs(handles) do
		local layer = LAYER_MT("/", {}, handle)
		layer.method = nil
		self.methods._all = true
		table.insert(self.stack, layer)
	end

	return self
end

for _, method in ipairs( methods ) do
	--- @param ... ExpressMiddleware
	--- @return ExpressRouterRoute
	ROUTE_MT[method] = function(self, ...)
		local handles = {...}
		-- PRINT({"route.lua ROUTE_MT", method = method, path = self.path, handles = handles})
		-- print(debug.traceback("ROUTE_MT"))
		for _, handle in ipairs(handles) do
			dprint(":%s('%s')", method, self.path)

			local layer = LAYER_MT("/", {}, handle)
			layer.method = method
			self.methods[method] = true
			table.insert(self.stack, layer)
		end

		return self
	end
end

return ROUTE_MT
