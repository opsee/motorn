local resty_resolver = require("resty.dns.resolver")
local resolver_addr = os.getenv("RESOLVERS")
assert(resolver_addr ~= nil, "RESOLVERS is not set, add resolvers (comma separated) in the RESOLVERS env var")

local resolvers = {}
local ir = 1

for r in resolver_addr:gmatch('[^,]+') do
    resolvers[ir] = r
    ir = ir + 1
end

local resolvcache = ngx.shared.resolver

local function arrsprint(table)
    local s = ""
    for i, v in ipairs(table) do
        if i ~= 1 then
            s = ", " .. s
        end
        s = s .. tostring(v)
    end
    return s
end


local function query(name)
    r, err = resty_resolver:new({
        nameservers = resolvers
    })

    if err then
        return nil, "not able to obtain a resolver from the set of specified addresses: " .. arrsprint(resolvers)
    end

    local answers, err = r:query(name)
    if not answers then
        return nil, "failed to get an answer from resolvers: " .. arrsprint(resolvers)
    end

    local answer = answers[1]
    if not answer then
        return nil, "failed to get an answer from resolvers for query: " .. name
    end

    if answer.errcode then
        return nil, "resolver returned error code: " .. tostring(answer.errcode)
    end

    if answer.cname then
        return _M.query(answer.cname)
    else
        return answer.address
    end
end

local _M = {}

function _M.query(name)
    local answer = resolvcache:get(name)
    if not answer then
        answer, err = query(name)
        if err then
            return nil, err
        end

        resolvcache:set(name, answer, 1)
    end

    return answer
end

return _M
