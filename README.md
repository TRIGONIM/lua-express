[![lua-express-banner](https://file.def.pm/v50V34N0.jpg)](https://luarocks.org/modules/AMD-NICK/lua-express)

A minimalistic web framework for Lua. High-quality port of [express.js](https://github.com/expressjs/express/)

[![LuaRocks](https://img.shields.io/luarocks/v/AMD-NICK/lua-express)](https://luarocks.org/modules/AMD-NICK/lua-express)
[![License](https://img.shields.io/github/license/TRIGONIM/lua-express)](LICENSE)
[![Repo Size](https://img.shields.io/github/repo-size/TRIGONIM/lua-express)](https://github.com/TRIGONIM/lua-express/archive/refs/heads/master.zip)
[![Docker Image Size](https://img.shields.io/docker/image-size/defaced/lua-express?label=docker%20image)](https://hub.docker.com/r/defaced/lua-express)


```lua
local express = require("express")
local app = express()

app:get("/", function(_, res)
	res:send("Hello World!")
end)

app:listen(3000)
```

## Installation:

```bash
luarocks install lua-express
```

## Features:

- ✅ Same features as the original express (except of rendering engine. temporarily) +
- 🧩 Easy to embed into any existing lua applications of any complexity
- 🪶 Lowest possible number of third-party dependencies
- 🪞 API similarity with express.js is almost 100%. Even in small details
- 🚀 Asynchronous (non-blocking) processing of incoming requests
- 🛠️  Easy to extend and modify with third-party modules
- 🏋️‍♂️ Several highly loaded web applications are already running on lua-express right now.


## Dependencies

- [pegasus](https://github.com/EvandroLG/pegasus.lua) – minimalistic web server
- [luasocket](https://github.com/lunarmodules/luasocket) – shipped with pegasus
- [copas](https://github.com/lunarmodules/copas/) (optional in the feature) – non-blocking processing of incoming requests. Also useful to make mysql/redis/http-client libs asynchronous
- [cjson](https://luarocks.org/modules/openresty/lua-cjson) (optional. Only if the `res:json(obj)` function is required)


## Development:

```bash
luarocks install copas
luarocks install pegasus

# only for res:json(obj)
# luarocks install lua-cjson

# not sure if this is really needed
# luarocks install luasec

git https://github.com/TRIGONIM/lua-express && cd lua-express

# add local module path to LUA_PATH env
export LUA_PATH="$(pwd)/lua/?.lua;$(pwd)/lua/?/init.lua;$LUA_PATH"

# do what you want.
lua examples/cookie.lua

# commit and pull request
```
