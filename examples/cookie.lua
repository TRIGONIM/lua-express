-- package.path = package.path .. ";../lua/?.lua;../lua/?/init.lua"

local express = require("express")
local app = express()

-- cookie parser middleware
app:use(function(req, _, next)
	local cookie = req:get("cookie")
	if cookie then
		local cookies = {}
		for k, v in cookie:gmatch("([^=]+)=([^;]+)") do
			cookies[k] = v
		end
		req.cookies = cookies
	else
		req.cookies = {}
	end
	next()
end)

local SECRET = "SyperS3cret"

app:get("/", function(req, res)
	local secret = req.cookies.secret
	if secret == SECRET then
		res:send("Hello")
	else
		res:setstatus(403):send("You don't know the secret")
	end
end)

app:get("/secret", function(req, res)
	res:cookie("secret", SECRET, {maxAge = 10}):send("Now you can access the site for 10 seconds")
end)

app:listen(3000)
