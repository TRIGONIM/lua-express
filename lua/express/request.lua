local getPathname = require("express.utils").getPathname
-- local dprint      = require("express.utils").debugPrint
local proxyaddr   = require("express.misc.proxy_addr")
local accepts     = require("express.misc.accepts")

--- @class ExpressRequest
--- @field params table? `app:get("/user/:id", ...)` -> req.params.id
--- @field query table? querystring parsed
--- @field baseUrl string /prefixed/route for router:get("/info", ...)
--- @field originalUrl string /prefixed/route/info for router:get("/info", ...)
local REQ_MT = {}
REQ_MT.__index = REQ_MT

function REQ_MT:get(name)
	return self.headers[ name:lower() ]
end
REQ_MT.header = REQ_MT.get

--- @return false|string `false` if not accepted, or mime type `string` if accepted
function REQ_MT:accepts(...)
	local types = {...}

	for _, type in ipairs(types) do
		local header_accept = self:get("accept")
		if not header_accept then return false end

		local accepted = accepts(header_accept, type)
		if accepted then return accepted end
	end

	return false
end

-- function REQ_MT:acceptsEncodings(...) end
-- function REQ_MT:acceptsCharsets(...) end
-- function REQ_MT:acceptsLanguages(...) end

-- Parse Range header field, capping to the given `size`.
-- function REQ_MT:range(size, options) end

-- Return the value of param `name` when present or `defaultValue`.
-- - Checks route placeholders, ex: _/user/:id_
-- - Checks body params, ex: id=12, {"id":12}
-- - Checks query string params, ex: ?id=12
function REQ_MT:param(name, defaultValue)
	local params = self.params or {}
	local body   = self.body   or {}
	local query  = self.query  or {}
	return params[name] or body[name] or query[name] or defaultValue
end

-- Check if the incoming request contains the "Content-Type"
-- header field, and it contains the given mime `type`.
-- function REQ_MT:is(...) local types = {...} end

--- @return "https"|"http"
function REQ_MT:protocol()
	-- #todo https://github.com/brunoos/luasec/wiki/LuaSec-1.3.x#conngetpeercertificaten
	-- Пока что не уверен, что правильно реализовал, поскольку не понимаю как заменить нодовский this.connection.encrypted

	local proto = "http"
	if self.socket.info then -- функция, которой нет, если в параметрах сервера не указать sslparams
		proto = "https"
	end

	local trust = self.app.settings["trust proxy fn"]
	if not trust(self._ipaddr, 0) then
		return proto
	end

	local header = self:get("X-Forwarded-Proto") or proto
	if header:find(",") then
		return header:match("(.+),") -- take first
	end

	return header
end

-- Short-hand for: req:protocol() == 'https'
function REQ_MT:secure()
	return self:protocol() == "https"
end

-- Return the remote address from the trusted proxy.
-- The is the remote address on the socket unless "trust proxy" is set.
--- @return string ip address
function REQ_MT:ip()
	local trust = self.app.settings["trust proxy fn"]
	return proxyaddr.proxyaddr(self, trust)
end


-- function REQ_MT:ips() -- #todo пока что лень реализовывать
-- 	local trust = self.app.settings["trust proxy fn"]
-- 	local addrs = {}
-- 	return addrs
-- end

-- Return subdomains as an array.
-- function REQ_MT:subdomains(...) end

function REQ_MT:path()
	return getPathname(self.url)
end

function REQ_MT:hostname()
	local trust = self.app.settings["trust proxy fn"]
	local host = self:get("X-Forwarded-Host")

	if not host or not trust(self._ipaddr, 0) then
		host = self:get("Host")
	elseif host:find(",") then
		host = host:match("(.+),") -- 1st host
	end

	if host then
		return host:match("^(.-):?%d*$") -- убирает порт в конце (если есть)
	end
end

-- Check if the request is fresh, aka Last-Modified and/or the ETag still match.
-- function REQ_MT:fresh() -- #todo не реализована одна функция
-- 	local method = self.method
-- 	local res = self.res
-- 	local status = res.pg_res.status

-- 	if method ~= "GET" and method ~= "HEAD" then return false end

-- 	if status >= 200 and status < 300 or status == 304 then
-- 		return fresh(self.headers, { -- #todo реализовать fresh: https://github.com/jshttp/fresh/blob/master/index.js
-- 			["etag"] = res:get("ETag"),
-- 			["last-modified"] = res:get("Last-Modified")
-- 		})
-- 	end

-- 	return false
-- end

-- function REQ_MT:stale()
-- 	return not self:fresh()
-- end

-- Check if the request was an _XMLHttpRequest_.
function REQ_MT:xhr()
	local val = self:get("X-Requested-With") or ""
	return val:lower() == "xmlhttprequest"
end

return REQ_MT
