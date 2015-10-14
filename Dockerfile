# based on https://github.com/ficusio/openresty/blob/master/alpine/Dockerfile

FROM alpine:3.2

ENV OPENRESTY_VERSION 1.9.3.1
ENV OPENRESTY_PREFIX /opt/openresty
ENV LUAJIT_VERSION 2.1
ENV NGINX_PREFIX /opt/openresty/nginx
ENV VAR_PREFIX /var/nginx

# NginX prefix is automatically set by OpenResty to $OPENRESTY_PREFIX/nginx
# look for $ngx_prefix in https://github.com/openresty/ngx_openresty/blob/master/util/configure

RUN echo "==> Installing openresty..." \
 && apk update \
 && apk add make gcc musl-dev \
    pcre-dev openssl-dev zlib-dev ncurses-dev readline-dev \
    curl perl sudo nettle-dev git \
 && mkdir -p /root/ngx_openresty \
 && cd /root/ngx_openresty \
 && echo "==> Downloading OpenResty..." \
 && curl -sSL http://openresty.org/download/ngx_openresty-${OPENRESTY_VERSION}.tar.gz | tar -xvz \
 && cd ngx_openresty-* \
 && echo "==> Configuring OpenResty..." \
 && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
 && echo "using upto $NPROC threads" \
 && ./configure \
    --prefix=$OPENRESTY_PREFIX \
    --http-client-body-temp-path=$VAR_PREFIX/client_body_temp \
    --http-proxy-temp-path=$VAR_PREFIX/proxy_temp \
    --http-log-path=$VAR_PREFIX/access.log \
    --error-log-path=$VAR_PREFIX/error.log \
    --pid-path=$VAR_PREFIX/nginx.pid \
    --lock-path=$VAR_PREFIX/nginx.lock \
    --with-luajit \
    --with-pcre-jit \
    --with-ipv6 \
    --with-http_ssl_module \
    --without-http_ssi_module \
    --without-http_userid_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    -j${NPROC} \
 && echo "==> Building OpenResty..." \
 && make -j${NPROC} \
 && echo "==> Installing OpenResty..." \
 && make install \
 && echo "==> Finishing..." \
 && ln -sf $NGINX_PREFIX/sbin/nginx /usr/local/bin/nginx \
 && ln -sf $NGINX_PREFIX/sbin/nginx /usr/local/bin/openresty \
 && ln -sf $OPENRESTY_PREFIX/bin/resty /usr/local/bin/resty \
 && ln -sf $OPENRESTY_PREFIX/luajit/bin/luajit-* $OPENRESTY_PREFIX/luajit/bin/lua \
 && ln -sf $OPENRESTY_PREFIX/luajit/bin/luajit-* /usr/local/bin/lua

# nettle for aes-gcm
RUN cd /tmp && git clone https://github.com/bungle/lua-resty-nettle.git \
  && mv lua-resty-nettle/lib/resty/* "${OPENRESTY_PREFIX}/lualib/resty/" \
  && rm -rf /tmp/lua-resty-nettle

# luarocks (is it really necessary?)
RUN echo "==> Installing luarocks..." \
 && wget -qO- http://luarocks.org/releases/luarocks-2.2.0.tar.gz | tar xvz -C /tmp/ \
 && cd /tmp/luarocks-* \
 && ./configure --with-lua="${OPENRESTY_PREFIX}/luajit" \
    --with-lua-include="${OPENRESTY_PREFIX}/luajit/include/luajit-${LUAJIT_VERSION}" \
    --with-lua-lib="${OPENRESTY_PREFIX}/lualib" \
 && make && make install

RUN sudo luarocks install lua-resty-template \
 && sudo luarocks install lua-resty-http

# slim down
RUN echo "==> Cleaning up..." \
 && apk del \
    make gcc musl-dev pcre-dev openssl-dev zlib-dev ncurses-dev readline-dev curl perl sudo git \
 && apk add \
    libpcrecpp libpcre16 libpcre32 openssl libssl1.0 pcre libgcc libstdc++ ca-certificates \
 && rm -rf /var/cache/apk/* \
 && rm -rf /root/ngx_openresty \
 && rm -rf /tmp/luarocks-*

WORKDIR $NGINX_PREFIX/

ENV JWE_KEY_FILE vape.test.key
ENV UPSTREAMS ""

RUN rm -rf conf/* html/*
COPY nginx $NGINX_PREFIX/

EXPOSE 80

CMD ["nginx", "-g", "daemon off; error_log /dev/stderr info;"]
