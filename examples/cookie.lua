-- package.path = package.path .. ";../lua/?.lua;../lua/?/init.lua"

local express = require("express")
local cookie_parser = require("cookie-parser") -- https://github.com/TRIGONIM/lua-express-middlewares
local app = express()

app:use( cookie_parser() )

local SECRET = "SyperS3cret"

app:get("/", function(req, res)
	local secret = req.cookies and req.cookies.secret
	if secret == SECRET then
		res:send("Hello")
	else
		res:status(403):send("You don't know the secret")
	end
end)

app:get("/secret", function(req, res)
	res:cookie("secret", SECRET, {maxAge = 10}):send("Now you can access the site for 10 seconds")
end)

app:listen(3000)
