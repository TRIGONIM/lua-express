local json_ok, json = pcall(require, "cjson")

--- @class ExpressResponse
local RES_MT = {}
RES_MT.__index = RES_MT

function RES_MT:status(code)
	local status_text
	if code == 429 then status_text = "Too Many Requests" end -- https://github.com/EvandroLG/pegasus.lua/pull/134
	self.pg_res:statusCode(code, status_text)
	return self
end

-- Set Link header field with the given `links`.
-- https://github.com/expressjs/express/blob/2a00da2067b7017f769c9100205a2a5f267a884b/lib/response.js#L67
function RES_MT:links(links)
	local link = self:get("Link") or ""
	if link ~= "" then link = link .. ", " end

	local lks = {}
	for k, v in pairs(links) do
		table.insert(lks, string.format('<%s>; rel="%s"', k, v))
	end

	return self:set("Link", link .. table.concat(lks, ", "))
end

-- send text or table as json https://expressjs.com/en/5x/api.html#res.send
function RES_MT:send(body)
	local chunk = body or ""
	local encoding
	local req = self.req
	local typ

	local app = self.app

	if tonumber(chunk) then
		if not self:get("Content-Type") then
			self:set("Content-Type", "text/plain; charset=utf-8")
		end
	end

	local ty = type(chunk)
	if ty == "string" then
		if not self:get("Content-Type") then
			self:set("Content-Type", "text/html; charset=utf-8")
		end
	elseif ty == "table" then
		return self:json(chunk)
	end

	-- etag можно позаимствовать тут: https://github.com/creationix/weblit/blob/master/libs/weblit-etag-cache.lua
	local etagFn = app.settings["etag fn"] -- #todo пока что функция не реализована и etag никогда не делается, хотя код ниже подготовлен
	local generateETag = self:get("ETag") and type(etagFn) == "function"

	local len
	if chunk ~= "" then
		len = chunk:len()
		self:set("Content-Length", len)
	end

	local etag
	if generateETag and len then
		local etag = etagFn(chunk, encoding)
		if etag then self:set("ETag", etag) end
	end

	-- #todo :fresh не реализован
	-- if req:fresh() then self:status(304) end

	if self.pg_res.status == 204 or self.pg_res.status == 304 then
		self:set("Content-Type", nil)
		self:set("Content-Length", nil)
		self:set("Transfer-Encoding", nil)
		chunk = ""
	end

	if self.pg_res.status == 205 then
		self:set("Content-Length", 0)
		self:set("Transfer-Encoding", nil)
		chunk = ""
	end

	if req.method == "HEAD" then
		self.pg_res:sendOnlyHeaders()
	else
		self.pg_res:write(chunk)
	end

	return self
end

-- send table as json https://expressjs.com/en/5x/api.html#res.json
function RES_MT:json(obj)
	if not json_ok then
		print("cannot res:json(): cjson is not installed")
		return self
	end

	local jsn = json.encode(obj)

	if not self:get("Content-Type") then
		self:set("Content-Type", "application/json; charset=utf-8")
	end

	return self:send(jsn)
end

-- function RES_MT:jsonp() end

-- Упрощено от оригинала. Не знаю, могут ли быть ощутимые последствия, но маловероятно
function RES_MT:sendStatus(statusCode)
	return self.pg_res:writeDefaultErrorMessage(statusCode)
end

function RES_MT:sendFile(path) -- options, callback
	local ok = self.pg_res:sendFile(path)
	if not ok then
		self:sendStatus(404)
	end
	return self
end

-- function RES_MT:download(path, filename, options, callback) end
function RES_MT:type(typ)
	-- #todo mime.lookup https://github.com/tst2005/lua-mimetypes/blob/fd570b2dff729b430c42d7bd6a767c197d38384b/mimetypes.lua#L1107
	return self:set("Content-Type", typ)
end
-- function RES_MT:format(obj) end
-- function RES_MT:attachment(filename) end

-- Append additional header `field` with value `val`.
-- Example:
--    res:append('Link', ['<http://localhost/>', '<http://localhost:3000/>'])
--    res:append('Set-Cookie', 'foo=bar; Path=/; HttpOnly')
--    res:append('Warning', '199 Miscellaneous warning')
function RES_MT:append(header, values)
	values = type(values) == "table" and values or {values}

    local prev = self:get(header)
    local val  = table.concat(values, ", ")

    if prev then
        val = prev .. ", " .. val
    end

    return self:set(header, val)
end


-- set headers https://expressjs.com/en/5x/api.html#res.set
function RES_MT:set(header_name, value)
	if type(header_name) == "table" then
		self.pg_res:addHeaders(header_name)
	else
		self.pg_res:addHeader(header_name, value)
	end
	return self
end
RES_MT.header = RES_MT.set

-- get value for header `field`
function RES_MT:get(field)
	return self.pg_res._headers[field]
end

function RES_MT:clearCookie(name, options)
	local opts = options or {}
	opts.expires = "Thu, 01 Jan 1970 00:00:00 GMT"
	opts.path = "/"
	return self:cookie(name, "", opts)
end

function RES_MT:cookie(name, value, options)
	local opts = options or {}
	if opts.maxAge then
		opts.Expires = os.date("!%a, %d %b %Y %H:%M:%S GMT", os.time() + opts.maxAge)
		opts["Max-Age"] = opts.maxAge
		opts.maxAge = nil
	end

	if not opts.path then
		opts.path = "/"
	end

	local cookie = name .. "=" .. value
	for k, v in pairs(opts) do
		cookie = cookie .. "; " .. k .. "=" .. v
	end
	return self:append("Set-Cookie", cookie)
end

-- Set the location header to `url`.
-- The given `url` can also be "back", which redirects to the _Referrer_ or _Referer_ headers or "/".
function RES_MT:location(url) -- redirect
	local loc = url

	if url == "back" then
		loc = self.req:get("Referrer") or "/"
	end

	return self:set("Location", loc) -- #todo urlencode
end

-- Redirect to the given `url` with optional response `status` defaulting to 302.
function RES_MT:redirect(url, status)
	local address = self:location(url):get("Location")
	local body

	local html = [[
		<html>
			<head>
				<title>Redirecting to %s</title>
			</head>
			<body>
				Redirecting to <a href="%s">%s</a>.
			</body>
		</html>
	]]

	if self.req:accepts("html") then
		body = string.format(html, address, address, address)
	else
		body = "Redirecting to " .. address .. "."
	end

	self:status(status or 302):set("Content-Length", body:len())

	if self.req.method == "HEAD" then
		self.pg_res:sendOnlyHeaders()
	else
		self:send(body)
	end
end

-- function RES_MT:vary(fields) end -- wtf
-- function RES_MT:render(view, options, callback) end

return RES_MT
