local PG_Request   = require("pegasus.request")
local PG_Response  = require("pegasus.response")

local copas        = require("copas")
local socket       = require("socket")

local finalhandler = require("express.misc.finalhandler")
local methods      = require("express.misc.methods")
local proxyaddr    = require("express.misc.proxy_addr")

local dprint       = require("express.utils").debugPrint

local unpack = unpack or table.unpack


--- @class ExpressRequest
--- @field res ExpressResponse
--- @field next fun(err?: any) #todo describe as @alias somewhere

--- @class ExpressResponse
--- @field req ExpressRequest

--- @class ExpressApplication
--- @field parent ExpressApplication?
local APP_MT = {}
APP_MT.__index = APP_MT

function APP_MT:init()
	-- self.cache = {} -- только для self:render()
	-- self.engines = {} -- in several places
	self.settings = {}

	self:defaultConfiguration();
end

function APP_MT:defaultConfiguration()
	local env = os.getenv("LUA_ENV") or "development"

	self:enable("x-powered-by")
	self:set("etag", "weak") -- #todo
	self:set("env", env)
	-- self:set("query parser", "extended") -- #todo не реализовано?
	-- self:set("subdomain offset", 2) -- #todo не реализовано?
	self:set("trust proxy", false)

	dprint("booting in %s mode", env)

	self.mountpath = "/" -- #todo implement

	self.locals = {} -- #todo что это и зачем? Просто для удобства людей?
	self.locals.settings = self.settings -- тогда это зачем?

	if env == "production" then
		self:enable("view cache") -- #todo не реализовано?
	end
end

local ROUTER_MT = require("express.router")

function APP_MT:lazyrouter()
	if not self._router then
		self._router = ROUTER_MT({
			-- caseSensitive = -- #todo
			-- strict =
		})

		self._router:use(function(req, res, next) -- #todo self:get("query parser fn")
			req.query = req.pg_req.querystring -- #todo own function. pg_req should not be here
			next()
		end)
		self._router:use(function(req, res, next)
			if self:enabled("x-powered-by") then res.pg_res:addHeader("X-Powered-By", "LuaExpress") end

			req.res = res -- для доступа к res изнутри req. Обновления хедера Etag и Last-Modified (сам не понял)
			res.req = req -- Например, if req.method == HEAD: dontSendBody()
			req.next = next

			setmetatable(req, {__index = self.request})
			setmetatable(res, {__index = self.response})

			-- res.locals = {} -- #todo for the render feature I think

			next()
		end)
	end
end

---handle incoming requests. req should already have url, method, headers etc fields
---@param req ExpressRequest
---@param res ExpressResponse
---@param callback? fun(err?: any) -- it's error 404 if err is nil
function APP_MT:handle(req, res, callback)
	local router = self._router

	local done = callback or finalhandler(req, res, {
		onerror = function(err)
			dprint("finalhandler error: %s", err)
		end
	})

	if not router then
		dprint("No routes defined on app")
		done()
		return
	end

	router:handle(req, res, done)
end

local handleMiddleware = function(fn)

	--- @type ExpressMiddleware
	return function(req, res, next)
		local orig = req.app
		fn(req, res, function(err)
			setmetatable(req, { __index = orig.request }) -- #todo вроде убрал из express.lua и нижнее
			setmetatable(res, { __index = orig.response })
			next(err)
		end)
	end
end

---@param path string|function default "/"
---@param ... ExpressMiddleware
---@return ExpressApplication
function APP_MT:use(path, ...)
	local fns = {...}

	if type(path) == "function" then
		fns = {path, ...} -- #todo будут ли тут повторно работать три точки?
		path = "/"
	end

	assert(fns[1], "app:use() requires a middleware function")

	self:lazyrouter()
	local router = self._router

	for _, fn in ipairs( fns ) do
		-- app:use( express() )
		if type(fn) == "table" and fn.handle and fn.set then -- #todo что за .set ? Его в роутере нет и вообще в express не нахожу
			local app = fn
			dprint(":use app under %s", path)
			app.mountpath = path
			app.parent = self

			router:use(path, handleMiddleware(app))

			setmetatable(app.request,  {__index = self.request})
			setmetatable(app.response, {__index = self.response})
			-- setmetatable(app.engines,  {__index = self.engines})
			setmetatable(app.settings, {__index = self.settings})
		else
			local fnn = type(fn) == "table" and function(...) return fn:handle(...) end or fn -- router в app:use. #todo в оригинале там по сути __call в роутере, но я не могу сделать так же, потому что в lua функция это не объект
			router:use(path, fnn)
		end
	end


	return self
end

function APP_MT:route(path)
	self:lazyrouter()
	return self._router:route(path)
end

-- function APP_MT:engine() end

-- #todo в оригинале поддержка name == table (множество)
-- #note очень(!) прикольная штука.
-- https://expressjs.com/en/5x/api.html#app.param
function APP_MT:param(name, fn)
	self:lazyrouter()
	self._router:param(name, fn)
	return self
end

local compile_trust = function(val)
	if type(val) == "function" then return val end
	if val == true then return function() return true end end
	if type(val) == "number" then return function(_, i) return i <= val end end

	if type(val) == "string" then
		local vals = {}
		for v in val:gmatch("[^,]+") do
			table.insert(vals, v:match("^%s*(.-)%s*$")) -- trim
		end
		val = vals
	end

	return proxyaddr.compile(val or {})
end

function APP_MT:set(setting, value)
	dprint("set '%s' to %s", setting, value)
	self.settings[setting] = value

	if setting == "trust proxy" then
		self:set("trust proxy fn", compile_trust(value))
	-- elseif setting == "etag" then -- #todo
	-- 	self:set("etag fn", function() end)
	-- elseif setting == "query parser" then
	-- 	self:set("query parser fn", function() end)
	end

	return self
end

-- #todo прописано в ipairs(methods). Мда
-- function APP_MT:get(setting) return self.settings[setting] end

function APP_MT:path()
	return self.parent and (self.parent:path() .. self.mountpath) or ""
end

function APP_MT:enabled(setting)
	return not not self:get(setting)
end

-- #todo закомментить по ненадобности? Глупо же
function APP_MT:disabled(setting)
	return not self:get(setting)
end

-- #todo поудалять все эти enable, enabled, disabled. В коде тоже убрать, если юзается. Оставить :set. В заметках про luaexpress так и сказать, что этого говнища нет
function APP_MT:enable(setting)
	return self:set(setting, true)
end

-- omg
function APP_MT:disable(setting)
	return self:set(setting, false)
end

--- @alias ExpressApplicationMethod fun(self: ExpressApplication, path: string, ...: function): ExpressApplication

--- #todo Annotate dynamically https://github.com/LuaLS/lua-language-server/discussions/2444
--- The same shit in router/init.lua

--- @class ExpressApplication
--- @field get ExpressApplicationMethod
--- @field post ExpressApplicationMethod
---- @field head ExpressApplicationMethod
---- @field options ExpressApplicationMethod


for _, method in ipairs( methods ) do
	APP_MT[method] = function(self, path, ...) -- ... is callbacks
		local callbacks = {...}

		-- #todo убрать отсюда .get и заменить на какой-то .getsetting или просто .setting(name)
		if method == "get" and not callbacks[1] then -- app:get(setting_name)
			return self.settings[path]
		end

		self:lazyrouter()

		local route = self._router:route(path)
		-- #todo тут не уверен. Ниже оригинал и дальше моя реализация
		-- route[method].apply(route, slice.call(arguments, 1));
		-- PRINT({"APP_MT[method] = function..", callbacks = callbacks, path = path})
		route[method](route, unpack(callbacks)) -- pass self (apply)
		return self
	end
end

function APP_MT:all(path, ...) --- ... is callbacks
	self:lazyrouter()
	local route = self._router:route(path) -- #todo не реализовано

	local cbs = {...}
	for _, method in ipairs(methods) do
		route[method](route, unpack( cbs ))
	end

	return self
end

-- #todo массивно, сейчас не хочу углубляться
-- function APP_MT:render() end

local wrap_req, wrap_res do
	--- @return ExpressRequest
	wrap_req = function(pg_req)
		--- @class ExpressRequest
		local req = {
			-- Is needed for express to be similar to nodejs

			url     = pg_req:path(), --- @type string /hello/world?foo=bar <br> /info for router:get("/info", ...)
			method  = pg_req:method(), --- @type string GET/POST etc
			headers = pg_req:headers(), --- @type table headers in lowercase

			socket  = pg_req.client, --- @type table socket object #todo make it userdata

			_ipaddr = pg_req.client:getpeername(), --- @type string? ip адрес сокет соединения (sock:getpeername()). В некоторых случаях почему-то был nil

			pg_req = pg_req, --- @type table #todo PegasusRequest instead of table
		}

		return setmetatable(req, {
			__index = pg_req
		})
	end

	-- extend ExpressResponse class
	--- @class ExpressResponse
	--- @field pg_res table #todo PegasusResponse instead of table

	--- @return ExpressResponse
	wrap_res = function(pg_res)
		return setmetatable({
			pg_res = pg_res,
		}, {
			__index = pg_res
		})
	end
end

-- #todo тут в оригинале вызывается функция с самого nodejs. Пришлось сделать свою реализацию
function APP_MT:listen(port, callback, host, sslparams)
	if type(callback) ~= "function" then
		sslparams = host
		host = callback
		callback = nil
	end

	host = host or "*"
	port = port or 3000

	-- sslparams = {
	-- 	wrap = {
	-- 		mode = "server",
	-- 		protocol = "any",
	-- 		key = "./pega/serverAkey.pem",
	-- 		certificate = "./pega/serverA.pem",
	-- 		cafile = "./pega/rootA.pem",
	-- 		verify = {"none"},
	-- 		options = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
	-- 	},
	-- 	sni = nil,
	-- },

	local server_sock, err = socket.bind(host, port)
	if not server_sock then
		return nil, "failed to create server socket; " .. tostring(err)
	end

	local server_ip, server_port = server_sock:getsockname()
	if not server_ip then
		return nil, "failed to get server socket name; " .. tostring(server_port)
	end

	-- Without this, asynchronous code such as timer.Simple(3, function() next() end)
	-- will not work and the application will close the connection before next() is executed.
	copas.autoclose = false
	copas.addserver(server_sock, copas.handler(function(client_sock)

		local pg_req = PG_Request:new(port, client_sock)
		if not pg_req:method() then client_sock:close() return end

		local writeHandler = {} -- crutch because of the pegasus.lua code (it should not be there)
		function writeHandler:processBodyData(body) return body end

		local pg_res = PG_Response:new(client_sock, writeHandler)
		pg_res:statusCode(200) -- without this request will be executed without default status as HTTP/0.9

		self:handle(wrap_req(pg_req), wrap_res(pg_res))
	end, sslparams))

	io.stderr:write("express.lua is up on " .. (sslparams and "https" or "http") .. "://" .. server_ip .. ":" .. server_port .. "/\n")
	-- /\ why not stdout? I dont remember

	if not copas.running then
		copas.loop(callback and function()
			callback(server_sock)
		end)
	elseif callback then
		callback(server_sock)
	end
end

return APP_MT
