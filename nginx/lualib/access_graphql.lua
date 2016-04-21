local origin = ngx.var.http_origin or ""
local cors, err = ngx.re.match(origin, "^https?://(.+)?(opsy\\.co|opsee\\.com?|localhost(:\\d+)|coreys-mbp-8(:\\d+))$", "ajo")
if (err == nil and cors ~= nil) then
  ngx.header["Access-Control-Allow-Methods"] = "GET,POST,PUT,PATCH,DELETE,HEAD"
  ngx.header["Access-Control-Max-Age"] = "1728000"
  ngx.header["Access-Control-Allow-Headers"] = "Accept-Encoding,Authorization,Content-Type"
  ngx.header["Access-Control-Allow-Origin"] = ngx.var.http_origin
  -- work around bartnet
  ngx.req.clear_header("Origin")
end

-- firstly, authorize the user
if ngx.var.request_method == "OPTIONS" then
  local user = true
  ngx.exit(ngx.HTTP_OK)
else
  local user = jose.auth_by_header()
end
