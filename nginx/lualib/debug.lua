local template = require "resty.template"
local auth_header = ngx.var.http_authorization
local _, _, token_string = string.find(auth_header, "Basic%s+(.+)")
local user_json = ngx.decode_base64(token_string)
local user = cjson.decode(user_json)
local routes = {};
local route_keys = ngx.shared.api_routes:get_keys(100)

for _, k in ipairs(route_keys) do
  v = ngx.shared.api_routes:get(k)
  routes[k] = v
end

template.cache = {}
template.caching(false)
template.render("debug.html", { 
  title = "Opsee debug",
  headers = ngx.req.get_headers(),
  user = user,
  routes = routes
})
