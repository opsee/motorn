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

local httpc = http.new()

for upstream in upstream_list:gmatch('[^,]+') do
  local res, err = httpc:request_uri(upstream .. "/api/swagger.json", {
    method = "GET",
    headers = {
      ["Content-Type"] = "application/json",
    }
  })

  if not res then
    ngx.log(ngx.ERR, "could not get upstream swagger. upstream: " .. upstream .. " error: " .. err)
  end

  local s, err, _ = swagger:set(upstream, res.body)
  if not s then
    ngx.log(ngx.ERR, "could not set swagger in cache" .. err)
  end

  local swagtable = cjson.decode(res.body)
  for p, _ in pairs(swagtable.paths) do
    local path = p:match('^/([^/]+)/?.*$')
    if path then
      local s, err, _ = api_routes:set(path, upstream)
      if not s then
        ngx.log(ngx.ERR, "could not set route in cache" .. err)
      end
    end
  end
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
