local aes = require("resty.nettle.aes")
local cjson = require("cjson")
local keyfile = os.getenv("JWE_KEY_FILE")

assert(keyfile ~= nil, "JWE Key file location isn't set, please set the JWE_KEY_FILE environment variable.")

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read "*a"
  file:close()
  return content
end

local secret = read_file(keyfile)

assert(secret ~= nil, "Not able to read the secret key file: " .. keyfile .. ". Does it exist?")

local function parse(token_str)
  if not token_str then
    return nil
  end

  local header, key, iv, ciphertext, tag = string.match(
    token_str,
    '^([^%.]+)%.([^%.]+)%.([^%.]+).([^%.]+).([^%.]+)$'
  )

  if not (header and key and iv and ciphertext and tag) then
    return nil
  end

  return {
    raw_header = header,
    header = decode_part(header, true),
    key = decode_part(key),
    iv = decode_part(iv),
    ciphertext = decode_part(ciphertext),
    tag = decode_part(tag)
  }
end

function decode_part(b64_str, json_decode)
  local remainder = #b64_str % 4
  if remainder > 0 then
    b64_str = b64_str .. string.rep("=", 4 - remainder)
  end

  b64_str = string.gsub(b64_str, "-", "+")
  b64_str = string.gsub(b64_str, "_", "/")

  local data = ngx.decode_base64(b64_str)
  if not data then
    return nil
  end

  if json_decode then
    data = cjson.decode(data)
  end

  return data
end

local function unwrap(secretkey, enckey, header)
  if not (header.alg and header.enc and header.iv and header.tag) then
    ngx.log(ngx.WARN, "missing things in JOSE header")
    return nil
  end

  local keysize = string.len(secretkey)
  if keysize ~= 16 then
    ngx.log(ngx.WARN, "wrong size secret key bytes: " .. keysize)
    return nil
  end

  local tag = decode_part(header.tag)
  local iv = decode_part(header.iv)
  if not tag then
    ngx.log(ngx.WARN, "missing tag in header")
    return nil
  end
  if not iv then
    ngx.log(ngx.WARN, "missing iv in header")
    return nil
  end

  local aead = aes.new(secretkey, "gcm", iv)
  local cek, authtag = aead:decrypt(enckey)
  if not authtag then
    ngx.log(ngx.WARN, "missing tag in unwrap")
    return nil
  end

  -- strings < 32 bytes are interned in lua, so comparison is pretty much constant time
  if authtag ~= tag then
    ngx.log(ngx.WARN, "unwrap not authenticated")
    return nil
  end

  return cek
end

local function decrypt(aad, cek, iv, ciphertext, tag)
  local keysize = string.len(cek)
  if keysize ~= 16 then
    ngx.log(ngx.WARN, "wrong size cek bytes: " .. keysize)
    return nil
  end

  local aead = aes.new(cek, "gcm", iv, aad)
  local plaintext, authtag = aead:decrypt(ciphertext)
  if not authtag then
    ngx.log(ngx.WARN, "missing tag in decrypt")
    return nil
  end

  -- strings < 32 bytes are interned in lua, so comparison is pretty much constant time
  if authtag ~= tag then
    ngx.log(ngx.WARN, "decrypt not authenticated")
    return nil
  end

  return plaintext
end

local function verify(claims)
  if not (claims.exp or claims.nbf) then
    ngx.log(ngx.WARN, "no expiration or not-before given in claims")
    return false
  end

  local now = ngx.now()

  if type(claims.exp) == "number" and claims.exp < now then
    ngx.log(ngx.WARN, "claims expired on: " .. ngx.http_time(claims.exp))
    return false
  elseif type(claims.nbf) == "number" and claims.nbf > now then
    ngx.log(ngx.WARN, "claims not before: " .. ngx.http_time(claims.nbf))
    return false
  end

  return true
end

local jwt_claims = {
  exp = true,
  nbf = true,
  iat = true,
  sub = true
}

local M = {}

function M.auth_by_header()
  local auth_header = ngx.var.http_authorization

  if auth_header == nil then
    ngx.log(ngx.WARN, "No Authorization header")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
  end

  local _, _, token_string = string.find(auth_header, "Bearer%s+(.+)")
  local token = M.auth(token_string)

  if not token then
    ngx.log(ngx.WARN, "Token unauthorized")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
  end

  ngx.req.set_header("Authorization", "Basic " .. M.header_encode_token(token))

  return token
end

function M.auth(token_string)
  -- explode the token into its 5 parts
  -- (header, key, iv, ciphertext, tag)
  -- and base64 decode each part
  local token = parse(token_string)
  if not token then
    ngx.log(ngx.WARN, "token not parsed")
    return nil
  end

  -- decrypt the content encryption key according to the keywrap
  -- algorithm specified in the header
  local cek = unwrap(secret, token.key, token.header)
  if not cek then
    ngx.log(ngx.WARN, "cek not decrypted")
    return nil
  end

  -- use the cek to decrypt our ciphertext
  local plaintext = decrypt(token.raw_header, cek, token.iv, token.ciphertext, token.tag)
  if not plaintext then
    ngx.log(ngx.WARN, "plaintext not decrypted")
    return nil
  end

  -- verify the claims contained within
  claims = cjson.decode(plaintext)
  if not claims then
    ngx.log(ngx.WARN, "claims could not be parsed")
    return nil
  end

  if verify(claims) then
    return claims
  end

  return nil
end

function M.header_encode_token(token)
  local filtered = {}
  for k, v in pairs(token) do
    if not jwt_claims[k] then
      filtered[k] = v
    end
  end

  return ngx.encode_base64(cjson.encode(token))
end

return M
