local resolver = require("resolver")

-- firstly, authorize the user
if ngx.var.request_method == "OPTIONS" then
  local user = true
  local origin = ngx.var.http_origin or ""
  local cors, err = ngx.re.match(origin, "^https?://(\\w+\\.)?(opsy\\.co|opsee\\.com?|localhost(:\\d+)|coreys-mbp-8(:\\d+))$", "ajo")
  if (err ~= nil or cors == nil) then
    ngx.log(ngx.ERR, "CORS domain doesn't match: ", origin)
    ngx.exit(ngx.HTTP_OK)
  end
  ngx.header["Access-Control-Allow-Methods"] = "GET,POST,PUT,PATCH,DELETE,HEAD"
  ngx.header["Access-Control-Max-Age"] = "1728000"
  ngx.header["Access-Control-Allow-Headers"] = "Accept-Encoding,Authorization,Content-Type"
  ngx.header["Access-Control-Allow-Origin"] = ngx.var.http_origin
  ngx.exit(ngx.HTTP_OK)
else
  local user = jose.auth_by_header()
end

-- capture the first part of the request path
local captures, err = ngx.re.match(ngx.var.uri, "^/([^/]+)/?.*$", "ajo")
if (err ~= nil or captures[1] == nil) then
  ngx.log(ngx.ERR, "no match in path")
  ngx.exit(ngx.HTTP_BAD_REQUEST)
end

-- look up the first segement of the request path in the routes cache
local route = captures[1]
local target = ngx.shared.api_routes:get(route)
if target == nil then
  -- if routes have already been loaded, then we don't really exist
  if ngx.shared.api_routes:get("_loaded") ~= nil then
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  -- load routes into the route cache and try our route again
  ngx.location.capture("/_preload")
  target = ngx.shared.api_routes:get(route)
  if target == nil then
    ngx.exit(ngx.HTTP_NOT_FOUND)
  end
end

-- resolve the upstream address
local captures, err = ngx.re.match(target, "^https://([^/]+)")
local hostname = captures[1]
if (err ~= nil or hostname == nil) then
  ngx.log(ngx.ERR, "no match for upstream host target: " .. target)
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local upstream, err = resolver.query(hostname)
if err then
    ngx.log(ngx.ERR, "unable to resolve upstream: " .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- set the upstream target and hostname
ngx.var.target = "https://" .. upstream
ngx.var.ssl_name = hostname
