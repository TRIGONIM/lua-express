local express = require("express")
local copas   = require("copas")
local socket  = require("socket")

local app = express()

-- handle disconnects
app:use(function(req, _, next)
	copas.addthread(function()
		local skt = req.socket

		while true do
			local ready_sockets_r, _, _ = socket.select({skt}, nil, 0)
			local client_disconnected = #ready_sockets_r == 1
			if client_disconnected then
				print("client_disconnected")
				req.disconnected = true
				break
			end
			copas.sleep(.1)
		end
	end)

	next()
end)

-- hold the request indefinitely
app:get("/", function(req, res)
	copas.addthread(function()
		while not req.disconnected do
			copas.sleep(.1)
		end
		print("req.disconnected")
	end)
end)

app:listen(3000)
