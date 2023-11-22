This example aims to show as many useful details in as little code as possible. Please read the comments to the code. They can save you a lot of time.

```bash
# optional. Needed in rare cases when luarocks or lua are installed incorrectly (like me)
# lrpath="/home/user/.luarocks"
# export LUA_PATH="$(pwd)/lua/?.lua;$(pwd)/lua/?/init.lua;$LUA_PATH"
# export LUA_PATH="$lrpath/share/lua/5.1/?.lua;$lrpath/share/lua/5.1/?/init.lua;$LUA_PATH"
# export LUA_CPATH=$lrpath/lib/lua/5.1/?.so
```

```bash
# git clone
export LUA_PATH="./?.lua;./?/init.lua;$LUA_PATH"
cd examples/simple-advanced
lua init.lua
```
