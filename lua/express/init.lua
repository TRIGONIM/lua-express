local express = setmetatable({}, {
	__call = function(self)
		return self.createApplication()
	end
})

local APP_MT = require("express.application")
local REQ_MT = require("express.request")
local RES_MT = require("express.response")

local ROUTER_MT = require("express.router")
local ROUTE_MT  = require("express.router.route")

--- @class ExpressApplication
--- @field request ExpressRequest
--- @field response ExpressResponse

--- @class ExpressRequest
--- @field app ExpressApplication

--- @class ExpressResponse
--- @field app ExpressApplication

--- @return ExpressApplication
express.createApplication = function()
	local app = setmetatable({}, APP_MT)

	app.request  = setmetatable({app = app}, REQ_MT)
	app.response = setmetatable({app = app}, RES_MT)

	app:init()
	return app
end

-- Expose the prototypes (metatables)
express.application = APP_MT
express.request     = REQ_MT
express.response    = RES_MT

express.Route  = ROUTE_MT;
express.Router = ROUTER_MT;

-- express.json = bodyParser.json
-- express.query = require('./middleware/query');
-- express.raw = bodyParser.raw
-- express.static = require('serve-static');
-- express.text = bodyParser.text
-- express.urlencoded = bodyParser.urlencoded

--- @alias ExpressMiddleware fun(req: ExpressRequest, res: ExpressResponse, next: fun(err?: any))

return express
