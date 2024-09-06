package.path = package.path .. ";../lua/?.lua;../lua/?/init.lua"

local express = require("express")
local app = express()

local path = require("express.misc.path")

-- Path to the directory where the files are stored on disk
-- Example: /home/user/name/lua/express/examples/downloads/files
local FILES_DIR = path.full( arg[0] ) .. "/files"

app:get("/", function(req, res)
	res:send("<ul>" ..
		"<li>Download <a href='/files/notes/groceries.txt'>notes/groceries.txt</a>.</li>" ..
		"<li>Download <a href='/files/amazing.txt'>amazing.txt</a>.</li>" ..
		"<li>Download <a href='/files/missing.txt'>missing.txt</a>.</li>" ..
		"<li>Download <a href='/files/CCTV大赛上海分赛区.txt'>CCTV大赛上海分赛区.txt</a>.</li>" ..
	"</ul>")
end)

app:get("/files/:file(*)", function(req, res, next)
	res:download(req.params.file, { root = FILES_DIR }, function(err)
		if not err then return end -- file sent
		if err.status ~= 404 then return next(err) end -- not a 404 error
		-- file to download not found
		res.statusCode = 404
		res:send("Cant find that file, sorry!")
	end)
end)

app:listen(3005)
