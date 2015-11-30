local resolver = require("resolver")
local user = true
local upstream_list = os.getenv("STREAMING_UPSTREAMS")

-- resolve the upstream address
-- currently there is only one websocket upstream, so this will need to be refactored
local captures, err = ngx.re.match(upstream_list, "^https://([^/]+)")
local hostname = captures[1]
if (err ~= nil or hostname == nil) then
  ngx.log(ngx.ERR, "no match for streaming upstream host target: " .. target)
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local upstream, err = resolver.query(hostname)
if err then
    ngx.log(ngx.ERR, "unable to resolve upstream: " .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- set the upstream target and hostname
ngx.var.target = "https://" .. upstream
ngx.log(ngx.INFO, "streaming upstream target: " .. ngx.var.target)
ngx.var.ssl_name = hostname
ngx.log(ngx.INFO, "streaming upstream ssl_name: " .. ngx.var.ssl_name)
