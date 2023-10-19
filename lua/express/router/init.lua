local ROUTE_MT = require("express.router.route")
local LAYER_MT = require("express.router.layer")
local methods  = require("express.misc.methods")

local dprint = require("express.utils").debugPrint

local getPathname = require("express.utils").getPathname

local ROUTER_MT = setmetatable({}, {
	__call  = function(self, options)
		local opts = options or {}

		return setmetatable({
			params = {},
			caseSensitive = opts.caseSensitive,
			-- mergeParams = opts.mergeParams, -- the reason of comment below in file
			strict = opts.strict,
			stack = {}
		}, self)
	end,
})
ROUTER_MT.__index = ROUTER_MT

function ROUTER_MT:param(name, fn)
	self.params[name] = self.params[name] or {}
	table.insert(self.params[name], fn)
	return self
end

local getProtohost = function(url)
	if type(url) ~= "string" or #url == 0 or url:sub(1, 1) == "/" then
		return nil
	end

	local searchIndex = url:find("?")
	local pathLength = searchIndex ~= nil and searchIndex or #url
	local fqdnIndex = url:sub(1, pathLength):find("://")

	return fqdnIndex ~= nil and url:sub(1, url:find("/", 3 + fqdnIndex)) or nil
end

local restore = function(fn, obj, ...) -- #todo chatgpt, не проверял
	local props = {...}
	local vals = {}

	for i = 1, #props do
		vals[i] = obj[props[i]]
	end

	return function(...)
		-- Восстанавливаем значения
		for i = 1, #props do
			obj[props[i]] = vals[i]
		end

		return fn(...)
	end
end

-- /en-US/docs/Web/API/Location/pathname
-- https://github.com/pillarjs/parseurl/blob/master/index.js
-- local teststrs = {
-- 	-- "/foo/B_lya/cyka/&*",
-- 	-- "/f0o/_Bar/?a=b&c=d",
-- 	-- "/foo_/Blya?a=b&c=d",
-- 	-- "/fO0o/",
-- 	-- "/foo/Bar",
-- 	-- "/",

-- 	"/f0o/_Bar/",
-- 	"/f0o/_Bar/baz",
-- 	"/f0o/_Bar/baz/b@x/",
-- }

-- for _,str in ipairs(teststrs) do
-- 	-- print( str:match("^(/[%w/_-]+)") )
-- 	print(str:match("^(.-)/?$"))
-- end

local matchLayer = function(layer, path)
	local ok, res = pcall(layer.match, layer, path)
	return res -- res or err
end

-- только для OPTIONS. Лень доделать просто
-- local appendMethods = function(list, addition)
-- 	local map = {}
-- 	for _,v in ipairs(list) do map[v] = true end

-- 	for _, v in ipairs(addition) do
-- 		if not map[v] then -- if not table.exist
-- 			table.insert(list, v)
-- 		end
-- 	end
-- end

function ROUTER_MT:handle(req, res, out)
	dprint("dispatching " .. req.method .. " " .. req.url) -- GET /about (для /birds/about из примера https://expressjs.com/ru/guide/routing.html)

	local idx = 1
	local protohost = getProtohost(req.url) or ""
	local removed = ""
	local slashAdded = false
	local sync = 1
	local paramcalled = {}

	-- store options for OPTIONS request
	-- only used if OPTIONS request
	-- local options = {} -- #todo не реализовано, ибо лень

	local stack = self.stack

	local parentParams = req.params
	local parentUrl = req.baseUrl or ""
	local done = restore(out, req, "baseUrl", "next", "params")

	local trim_prefix

	local function next(err)
		local layerError = err ~= "route" and err or nil

		-- remove added slash
		if slashAdded then
			req.url = req.url:sub(2)
			slashAdded = false
		end

		-- restore altered req.url
		if removed:len() ~= 0 then
			req.baseUrl = parentUrl
			req.url = protohost .. removed .. req.url:sub(#protohost + 1) -- было #protohost + #removed + 1, наверное GPT ошибся. При дебаге поменял
			removed = ""
		end

		-- signal to exit router
		if layerError == "router" then
			done()
			return
		end

		-- no more matching layers
		if idx > #stack then
			done(layerError)
			return
		end

		if sync >= 100 then
			return next(err)
		end
		-- max sync stack
		sync = sync + 1

		-- get pathname of request
		local path = getPathname( req.url )
		if not path then
			return done(layerError)
		end

		-- find next matching layer
		local layer, match, route
		while match ~= true and idx <= #stack do
			layer = stack[idx]
			idx = idx + 1
			match = matchLayer(layer, path) -- bool or err str
			route = layer.route

			if type(match) ~= "boolean" then
				layerError = layerError or match
			end

			if match ~= true then
				goto continue
			end

			if not route then
				goto continue
			end

			-- routes do not match with a pending error
			if layerError then
				match = false
				goto continue
			end

			local method = req.method
			local has_method = route:_handles_method(method)

			-- build up automatic options response
			-- if not has_method and method == "OPTIONS" then
			-- 	appendMethods(options, route:_options())
			-- end

			-- don't even bother matching route
			if not has_method and method ~= "HEAD" then
				match = false
			end

			::continue::
		end

		if match ~= true then
			return done(layerError)
		end

		if route then
			req.route = route
		end

		-- #todo not implemented. mergeParams выглядит лениво для реализации сейчас
		-- req.params = self.mergeParams and mergeParams(layer.params, parentParams) or layer.params
		req.params = layer.params

		local layerPath = layer.path

		self:process_params(layer, paramcalled, req, res, function(err)
			if err then
				next(layerError or err)
			elseif route then
				layer:handle_request(req, res, next)
			else
				trim_prefix(layer, layerError, layerPath, path)
			end

			sync = 1
		end)
	end

	function trim_prefix(layer, layerError, layerPath, path)
		if layerPath:len() ~= 0 then
			-- Validate path is a prefix match
			if layerPath ~= path:sub(1, layerPath:len()) then
				next(layerError)
				return
			end

			-- Validate path breaks on a path separator
			local c = path:sub(layerPath:len() + 1, layerPath:len() + 1) -- я так понял, это чтобы понять есть ли какой-то путь ПОСЛЕ /birds. Т.е. /birds/about например. Я встречал тут только "/", пока дебажил симметрично с реальным экспрессом
			if c ~= "" and c ~= "/" and c ~= "." then return next(layerError) end

			-- Trim off the part of the url that matches the route
			-- middleware (.use stuff) needs to have the path stripped
			-- dprint("trim_prefix BEFORE: " .. layerPath .. " from url " .. req.url)
			removed = layerPath
			req.url = protohost .. req.url:sub(protohost:len() + removed:len() + 1) -- req.url = /birds/about меняет на просто /about. #todo попробовать убрать +1 и проверить будет ли тоже /about получаться
			-- dprint("trim_prefix AFTER: " .. req.url)

			-- Ensure leading slash
			if protohost == "" and req.url:sub(1, 1) ~= "/" then
				req.url = "/" .. req.url
				slashAdded = true
			end

			-- Setup base URL (no trailing slash)
			req.baseUrl = parentUrl .. (removed:sub(-1) == "/" and removed:sub(1, -2) or removed) -- /birds (removed == /birds)
			dprint("Что тут baseUrl? ", req.baseUrl)
		end

		-- dprint("layer.name: " .. layer.name .. ", layerPath: " .. layerPath .. ", originalUrl: " .. req.originalUrl)

		if layerError then
			layer:handle_error(layerError, req, res, next)
		else
			layer:handle_request(req, res, next)
		end
	end

	req.next = next

	-- #todo not implemented (пока не критично)
	-- if req.method === "OPTIONS" then end

	req.baseUrl = parentUrl
	req.originalUrl = req.originalUrl or req.url

	next()
end

-- Process any parameters for the layer.
function ROUTER_MT:process_params(layer, called, req, res, done)
	local params = self.params

	-- captured parameters from the layer, keys and values
	local keys = layer.keys
	if #keys == 0 then return done() end

	local i = 0
	local paramIndex = 0
	local name, paramVal, paramCallbacks, paramCalled

	local param, paramCallback -- для доступа к каждой функции изнутри другой

	function param(err) -- localized above
		if err then return done(err) end
		if i >= #keys then return done() end

		paramIndex = 0
		i = i + 1
		name = keys[i]
		paramVal = req.params[name]
		paramCallbacks = params[name]
		paramCalled = called[name]

		if not paramVal or not paramCallbacks then
			return param()
		end

		-- param previously called with same value or error occurred
		if paramCalled and (paramCalled.match == paramVal
			or (paramCalled.error and paramCalled.error ~= "route")) then
			-- restore value
			req.params[name] = paramCalled.value

			-- next param
			return param(paramCalled.error)
		end

		called[name] = {
			error = nil,
			match = paramVal,
			value = paramVal, -- #todo зачем два одинаковых поля?
		}

		paramCalled = called[name]

		paramCallback()
	end

	-- single param callbacks
	function paramCallback(err)
		paramIndex = paramIndex + 1
		local fn = paramCallbacks[paramIndex]

		-- store updated value
		paramCalled.value = req.params[name]

		if err then
			paramCalled.error = err
			param(err)
			return
		end

		if not fn then return param() end

		local ok, res = pcall(fn, req, res, paramCallback, paramVal, name)
		if not ok then
			paramCallback(res)
		end
	end

	param()
end

-- Use the given middleware function, with optional path, defaulting to "/"
function ROUTER_MT:use(path, ...)
	local callbacks = {...}

	-- default path to '/'
	-- disambiguate router.use([fn])
	if type(path) == "function" then
		table.insert(callbacks, 1, path)
		path = "/"
	end

	if #callbacks == 0 then
		error("Router.use() requires a middleware function")
	end

	for _, fn in ipairs(callbacks) do
		local inf = debug.getinfo(fn, "S")
		local infstr = inf.short_src .. ":" .. inf.linedefined
		dprint("ROUTER_MT:use " .. path .. " " .. infstr) -- #todo debug.getinfo для fn, чтобы название вытащить, как в оригинале

		local layer = LAYER_MT(path, { -- #todo вроде никакие из опций не реализованы
			sensitive = self.caseSensitive,
			strict = false,
			["end"] = false,
		}, fn)

		layer.route = nil -- я так понял, это если :use вызвать после :route

		table.insert(self.stack, layer)
	end

	return self
end

-- Create a new Route for the given path
function ROUTER_MT:route(path)
	local route = ROUTE_MT(path)

	-- dprint("ROUTER_MT:route(" .. path .. ")")

	local layer = LAYER_MT(path, {
		sensitive = self.caseSensitive,
		strict = self.strict,
		["end"] = true,
	}, function(req, res, next)
		route:dispatch(req, res, next) -- один из вызовов был из LAYER_MT:handle_request. Не уверен, есть ли откуда-то еще
	end)

	layer.route = route

	table.insert(self.stack, layer)
	return route
end

local _add_method = function(method)
	ROUTER_MT[method] = function(self, path, ...)
		local route = self:route(path)
		-- dprint("routerR_MT:" .. method .. "(" .. path .. ")")
		route[method](route, ...)
		return self
	end
end

_add_method("all")
for _, method in ipairs(methods) do
	_add_method(method)
end

return ROUTER_MT
