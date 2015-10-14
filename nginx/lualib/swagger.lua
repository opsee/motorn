if not ngx.shared.api_routes:get("_loaded") then
  ngx.location.capture("/_preload")
end

local swagger = ngx.shared.swagger
local swagger_keys = swagger:get_keys(100)
local swagger_consumes = {}
local swagger_produces = {}
local swagtable = {
  swagger = "2.0",
  info = {
    title = "Swagger API",
    version = "0.0.1"
  },
  basePath = "/",
  consumes = {},
  produces = {},
  paths = {},
  definitions = {}
}

for _, k in ipairs(swagger_keys) do
  local swag = cjson.decode(swagger:get(k))
  if swag then
    for p, pv in pairs(swag.paths) do
      swagtable.paths[p] = pv
    end
    for d, dv in pairs(swag.definitions) do
      swagtable.definitions[d] = dv
    end
    for _, c in ipairs(swag.consumes) do
      swagger_consumes[c] = true
    end
    for _, p in ipairs(swag.produces) do
      swagger_produces[p] = true
    end
  end
end

local i = 1
for c, _ in pairs(swagger_consumes) do
  swagtable.consumes[i] = c
  i = i + 1
end

i = 1
for p, _ in pairs(swagger_produces) do
  swagtable.produces[i] = p
  i = i + 1
end

ngx.say(cjson.encode(swagtable))
