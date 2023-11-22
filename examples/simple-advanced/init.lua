local express = require("express")
local app = express()

local example_subroute = require("routes.example")

-- Example access-controller middleware
local function allow_only_even_seconds(req, res, next)
	if os.time() % 2 ~= 0 then
		res:status(403):send("Access to the site is only allowed during even-numbered seconds")
		return
	end

	if math.random(1, 2) == 1 then
		req.somevar = "Have a nice day"
	else
		req.somevar = "poop"
	end

	-- If we don't call this function, the client will wait indefinitely for a response from the site.
	-- This can be useful for performing a heavy asynchronous query to the database and return a response later.
	-- Or even for creating long-polling servers.
	next()
end

-- This function will be called on every request to the site.
-- Inside the function you can change req, res objects.
-- The changes will be available along the entire path,
-- while the request will "walk" through other middlewares and route handlers
app:use(allow_only_even_seconds)

-- basic route handler
app:get("/", function(req, res)
	res:send("Hello from GET /. I have a magic variable for you: " .. req.somevar)
end)

-- You can specify as many handlers as you want for a single route.
-- This can be useful for custom middlewares like auth_required or validators lime this mine:
-- https://gist.github.com/AMD-NICK/56577317d3355ff13b67bfb84b1f1d07
app:get("/multiple", function(req, res, next)
	print("We are in the first handler")
	next()
end, function(req, res, next)
	print("We are in the second handler")
	next()
end, function(req, res)
	res:send("Hello from GET /multiple")
end)

-- GET /prefixed/route/info, ...
app:use("/prefixed/route", example_subroute)


-- Error handlers look just like normal middlewares, but they have 4 arguments instead of 3.
-- If you specify less than 4 arguments, this handler stops being an error handler.
-- Errors can be a table. Errors can be thrown via next("str" or {}) or via error()
-- Throw example in routes/example.lua
app:use(function(err, req, res, next)
	local is_production = os.getenv("LUA_ENV") == "production"
	print("🆘 Error", err, "production?:", is_production)
	if is_production then
		res:status(500):send("Internal server error")
	else
		-- pass to finalhandler with detailed error response
		-- https://github.com/TRIGONIM/lua-express/blob/main/lua/express/misc/finalhandler.lua
		next(err)
	end
end)

-- advanced app:listen example
app:listen(3000, function(server_sock)
	local ip, port = server_sock:getsockname()
	print("🔥 Server started on " .. ip .. ":" .. port)
end)
