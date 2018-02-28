local M = {}

local io = io
local string = string
local tostring = tostring
local ngx = ngx

local ffi = require "ffi"
local util = require "shuaicj.upload.util"

ffi.cdef[[
typedef struct SHAstate_st
{
    unsigned int h0,h1,h2,h3,h4;
    unsigned int Nl,Nh;
    unsigned int data[16];
    unsigned int num;
} SHA_CTX;

int SHA1_Init(SHA_CTX *shactx);
int SHA1_Update(SHA_CTX *shactx, const void *data, unsigned long len);
int SHA1_Final(unsigned char *md, SHA_CTX *shactx);
]]


M.header = "X-Checksum-SHA1"

function M.check_headers(ctx, headers)
    local v = headers[M.header]
    if v and #v == 40 and string.match(v, "^%x+$") then
        ctx.checksum.sha1 = {
            header = M.header,
            client = v
        }
        return
    end

    local s = string.format("%s [%s] illegal", M.header, tostring(v))
    ngx.log(ngx.WARN, s)
    return util.exit(400, s)
end

function M.verify_checksum(ctx)
    local sha1_ctx = ffi.new("SHA_CTX")
    if ffi.C.SHA1_Init(sha1_ctx) == 0 then
        ngx.log(ngx.ERR, "SHA1_Init failed")
        return util.exit(500, "SHA1_Init failed")
    end

    local f, e = io.open(ctx.file_path, "rb")
    if not f then
        ngx.log(ngx.ERR, e)
        return util.exit(500, e)
    end

    while true do
        local data = f:read(4096)
        if not data then
            f:close()
            break
        end
        if ffi.C.SHA1_Update(sha1_ctx, data, #data) == 0 then
            ngx.log(ngx.ERR, "SHA1_Update failed")
            return util.exit(500, "SHA1_Update failed")
        end
    end

    local checksum = ffi.new("char[20]")
    if ffi.C.SHA1_Final(checksum, sha1_ctx) == 0 then
        ngx.log(ngx.ERR, "SHA1_Final failed")
        return util.exit(500, "SHA1_Final failed")
    end

    checksum = util.tohex(ffi.string(checksum, 20))
    ctx.checksum.sha1.server = checksum

    if ctx.checksum.sha1.client ~= checksum then
        util.truncate_file(ctx.file_path)
        ctx.real_size = 0
        local s = string.format("SHA1 conflict. client [%s], server [%s]",
            ctx.checksum.sha1.client, checksum)
        ngx.log(ngx.ERR, s)
        return util.exit(409, s, ctx)
    else
        ngx.log(ngx.INFO, string.format("SHA1 match. file[%s] MD5 [%s]", ctx.file_path, checksum))
    end
end

return M
