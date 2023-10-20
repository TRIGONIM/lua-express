local PG_Request   = require("pegasus.request")
local PG_Response  = require("pegasus.response")

local copas        = require("copas")
local socket       = require("socket")

local finalhandler = require("express.misc.finalhandler")
local methods      = require("express.misc.methods")

local dprint       = require("express.utils").debugPrint

local unpack = unpack or table.unpack


local APP_MT = {}
APP_MT.__index = APP_MT

function APP_MT:init()
	-- self.cache = {} -- только для self:render()
	-- self.engines = {}
	self.settings = {}

	self:defaultConfiguration();
end

function APP_MT:defaultConfiguration()
	local env = os.getenv("LUA_ENV") or "development"

	self:enable("x-powered-by")

	dprint("booting in " .. env .. " mode")

	self.mountpath = "/" -- pegasus:new{location = "/"}

	self.locals = {} -- #todo что это и зачем? Просто для удобства людей?
	self.locals.settings = self.settings -- тогда это зачем?

	-- // default configuration
	-- this.set('view', View);
	-- this.set('views', resolve('views'));
	-- this.set('jsonp callback name', 'callback');

	if env == "production" then
		self:enable("view cache") -- #todo не реализовано?
	end
end

local ROUTER_MT = require("express.router")

-- local function setPrototypeOf(obj, prototype)
-- 	local mt = getmetatable(obj) or {}
-- 	mt.__index = prototype
-- 	setmetatable(obj, mt)
-- end

function APP_MT:lazyrouter()
	if not self._router then
		self._router = ROUTER_MT({
			-- caseSensitive = -- #todo
			-- strict =
		})

		-- self._router:use(function(req, res, next) -- #todo self:get("query parser fn")
		-- 	req.query = self.pegasus_res.querystring
		-- 	next()
		-- end)
		self._router:use(function(req, res, next)
			if self:enabled("x-powered-by") then res:addHeader("X-Powered-By", "LuaExpress") end -- #todo в этом месте еще нет собственной метатаблицы, поэтому используется метод от pegasus. Возможно, лучше перенести ниже и использовать :set для хедера

			req.res = res -- для доступа к res изнутри req. Обновления хедера Etag и Last-Modified (сам не понял)
			res.req = req -- Например, if req.method == HEAD: dontSendBody()
			req.next = next

			-- setPrototypeOf(req, self.request)
			-- setPrototypeOf(res, self.response)

			local req_mt = getmetatable(req)
			local res_mt = getmetatable(res)
			setmetatable(req_mt, {__index = self.request}) -- устанавливаем метатаблицу метатаблице для многоуровневого наследования
			setmetatable(res_mt, {__index = self.response})

			-- res.locals = {} -- #todo для рендера вроде

			next()
		end)
	end
end

function APP_MT:handle(req, res, callback)
	local router = self._router

	local done = callback or finalhandler(req, res, {
		onerror = function(err) -- './pega/application.lua:81: attempt to index field 'pegasus_res' (a nil value)'
			dprint("express ошибка:", err)
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
	return function(req, res, next)
		local orig = req.app -- #todo req.app реализован?
		fn(req, res, function(err)
			setmetatable(req, { __index = orig.request }) -- #todo вроде убрал из express.lua и нижнее
			setmetatable(res, { __index = orig.response })
			next(err)
		end)
	end
end

-- #todo функция абсолютно сырая и кажется, не будет работать
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
			dprint("APP_MT:use app under " .. path)
			app.mountpath = path
			app.parent = self

			router:use(path, handleMiddleware(app))

			setmetatable(app.request,  {__index = self.request})
			setmetatable(app.response, {__index = self.response})
			setmetatable(app.engines,  {__index = self.engines})
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

function APP_MT:set(setting, value)
	dprint("set " .. tostring(setting) .. " to " .. tostring(value))
	self.settings[setting] = value
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

for _, method in ipairs( methods ) do
	-- express.handlers[method] = express.handlers[method] or {}

	-- --- app:get(path, callback), app:post, etc
	-- APP_MT[method] = function(self, path, callback)
	-- 	express.handlers[method][path] = callback
	-- 	return nil
	-- end

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

-- #todo тут в оригинале вызывается функция с самого nodejs. Пришлось сделать свою реализацию
function APP_MT:listen(port, host, sslparams)
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

	copas.autoclose = false -- чтобы от next() в коде был смысл. Подробнее: https://t.me/c/1473957119/169428
	copas.addserver(server_sock, copas.handler(function(client_sock)

		local req = PG_Request:new(port, client_sock) -- #todo в будущем просто перенести функционал в сам express, чтобы не зависеть от pegasus. 🔥 Тогда можно будет и res:status вместо :setstatus вернуть
		if not req:method() then client_sock:close() return end

		local writeHandler = {} -- _writeHandler, костыль из-за кода pegasus.lua (его там не должно было быть)
		function writeHandler:processBodyData(body) return body end

		local res = PG_Response:new(client_sock, writeHandler)
		-- res.request = req -- #todo проверить, используется ли где-то. Если нет – удалить. В express есть res.req

		-- Нужно для express, чтобы быть похожим на настоящий nodejs
		req.url     = req:path() -- /bla/bla?kek=lol
		req.method  = req:method() -- GET/POST etc
		req.headers = req:headers() -- #todo в node они lower-case, тут не проверял. И в express вроде не используется, так что мб надо удалить
		-- res.headers = res._headers -- https://github.com/EvandroLG/pegasus.lua/blob/2a3f4671f45f5111c14793920771f96b819099ab/src/pegasus/response.lua#L103
		req.query   = req.querystring

		res:statusCode(200)
		-- res.headers = {}
		-- res:addHeader("Content-Type", "text/html")

		self:handle(req, res)
	end, sslparams))

	io.stderr:write("express.lua is up on " .. (sslparams and "https" or "http") .. "://" .. server_ip .. ":" .. server_port .. "/\n")

	return server_sock, nil
end

return APP_MT
