local resolver = require("resolver")
local lock = locker:new("locks")
local elapsed, err = lock:lock("api_routes")
if (elapsed == nil or elapsed > 0) then
  ngx.log(ngx.WARN, "failed to acquire api_routes lock: " .. err)
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local api_routes = ngx.shared.api_routes
local swagger = ngx.shared.swagger

local upstream_list = os.getenv("UPSTREAMS")
if not upstream_list then
  local ok, err = lock:unlock()
  if not ok then
    ngx.log(ngx.ERR, "failed to release api_routes lock: " .. err)
  end

  ngx.log(ngx.ERR, "no upstreams set in UPSTREAMS env var, what's the point")
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

for upstream in upstream_list:gmatch('[^,]+') do
  -- http client
  local httpc = http.new()

  -- resolve the upstream address
  local captures, err = ngx.re.match(upstream, "^https://([^/]+)")
  local hostname = captures[1]
  if (err ~= nil or hostname == nil) then
    ngx.log(ngx.ERR, "no match for upstream host target: " .. target)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end
  
  local u, err = resolver.query(hostname)
  if err then
    ngx.log(ngx.ERR, "unable to resolve upstream: " .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local ok, err = httpc:connect(u, 443)
  if err then
    ngx.log(ngx.ERR, "unable to establish connection with upstream: " .. u .. " error: " .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  -- ssl SNI handshake sending the hostname
  httpc:ssl_handshake(nil, hostname, true)

  local response, err = httpc:request({
    path = "/api/swagger.json",
    method = "GET",
    headers = {
      ["Host"] = hostname,
      ["Content-Type"] = "application/json",
    },
    ssl_verify = true,
  })

  if not response then
    ngx.log(ngx.ERR, "could not get upstream swagger. upstream: " .. upstream .. " error: " .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  ngx.log(ngx.ERR, "could not get upstream swagger. upstream: " .. upstream .. " status: " .. tostring(response.status))

  if not response.has_body then
    ngx.log(ngx.ERR, "could not get upstream swagger. upstream: " .. upstream .. " status: " .. tostring(response.status))
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local body = response:read_body()

  local s, err, _ = swagger:set(upstream, body)
  if not s then
    ngx.log(ngx.ERR, "could not set swagger in cache" .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local swagtable = cjson.decode(body)
  for p, _ in pairs(swagtable.paths) do
    local path = p:match('^/([^/]+)/?.*$')
    if path then
      local s, err, _ = api_routes:set(path, upstream)
      if not s then
        ngx.log(ngx.ERR, "could not set route in cache" .. err)
      end
    end
  end

  httpc:close()
end

api_routes:set("_loaded", "1")

local ok, err = lock:unlock()
if not ok then
  ngx.log(ngx.ERR, "failed to release api_routes lock: " .. err)
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

keys = api_routes:get_keys(100)
for _, k in ipairs(keys) do
  v = api_routes:get(k)
  routeline = "route: " .. k .. ", host: " .. v
  ngx.log(ngx.INFO, "preloaded routes: " .. routeline)
  ngx.say(routeline)
end
