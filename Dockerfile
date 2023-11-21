# Эта версия LuaJit используется в прогрессивной БД Tarantool, который заточен на производительность
# Здесь есть встроенный профайлер памяти: https://www.tarantool.io/en/doc/latest/reference/tooling/luajit_memprof/
# и функции для получения метрик компилятора: https://www.tarantool.io/ru/doc/latest/reference/tooling/luajit_getmetrics/

# USAGE:
# docker build -t lua-express:latest -f Dockerfile .
# docker run -v ./examples/:/app -p 3000:3000 lua-express:latest bash -c 'cd /app && lua cookie.lua'

# misc.memprof.start() doesn't work on the Alpine
FROM buildpack-deps:bullseye

RUN set -eux ; apt-get update && apt-get install -y \
	cmake

# luajit
RUN set -eux \
	&& LVP=/usr ; cd /tmp \
	&& git clone https://github.com/tarantool/luajit.git \
	&& mkdir luajit-build && cd luajit-build \
	&& cmake ../luajit -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=$LVP \
	&& cmake --build . --parallel \
	&& make install \
	&& cd /tmp && rm -rf luajit luajit-build

# luarocks
RUN set -eux \
	&& LVP=/usr ; cd /tmp \
	&& wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz \
	&& tar zxpf luarocks-3.9.2.tar.gz && rm luarocks-3.9.2.tar.gz \
	&& cd luarocks-3.9.2 \
	&& ln -s /usr/bin/luajit /usr/bin/lua \
	&& ./configure --with-lua=$LVP --with-lua-include=$LVP/include/luajit-2.1 --with-lua-interpreter=luajit \
	&& make && make install \
	&& cd /tmp && rm -rf luarocks-3.9.2

# required external packages
RUN set -eux && \
	luarocks install copas && \
	# optional, for https
	# luarocks install luasec && \
	luarocks install lua-cjson && \
	luarocks install pegasus

RUN rm -rf /var/lib/apt/lists/*

COPY ./lua /usr/local/share/lua/5.1

WORKDIR /usr/local/share/lua/5.1/express

