local M = {}

local io = io
local string = string
local tostring = tostring

local ffi = require "ffi"
local util = require "shuaicj.upload.util"

ffi.cdef[[
typedef unsigned long MD5_LONG;

enum {
    MD5_CBLOCK = 64,
    MD5_LBLOCK = MD5_CBLOCK/4
};

typedef struct MD5state_st
{
    MD5_LONG A,B,C,D;
    MD5_LONG Nl,Nh;
    MD5_LONG data[MD5_LBLOCK];
    unsigned int num;
} MD5_CTX;

int MD5_Init(MD5_CTX *c);
int MD5_Update(MD5_CTX *c, const void *data, size_t len);
int MD5_Final(unsigned char *md, MD5_CTX *c);
]]


M.header = "X-Checksum-MD5"

function M.check_headers(ctx, headers)
    local v = headers[M.header]
    if v and #v == 32 and string.match(v, "^%x+$") then
        ctx.checksum.md5 = {
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
    local md5_ctx = ffi.new("MD5_CTX")
    if ffi.C.MD5_Init(md5_ctx) == 0 then
        ngx.log(ngx.ERR, "MD5_Init failed")
        return util.exit(500, "MD5_Init failed")
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
        if ffi.C.MD5_Update(md5_ctx, data, #data) == 0 then
            ngx.log(ngx.ERR, "MD5_Update failed")
            return util.exit(500, "MD5_Update failed")
        end
    end

    local checksum = ffi.new("char[16]")
    if ffi.C.MD5_Final(checksum, md5_ctx) == 0 then
        ngx.log(ngx.ERR, "MD5_Final failed")
        return util.exit(500, "MD5_Final failed")
    end

    checksum = util.tohex(ffi.string(checksum, 16))
    ctx.checksum.md5.server = checksum

    if ctx.checksum.md5.client ~= checksum then
        util.truncate_file(ctx.file_path)
        ctx.real_size = 0
        local s = string.format("MD5 conflict. file[%s] client [%s], server [%s]",
            ctx.file_path, ctx.checksum.md5.client, checksum)
        ngx.log(ngx.ERR, s)
        return util.exit(409, s, ctx)
    else
        ngx.log(ngx.INFO, string.format("MD5 match. file[%s] MD5 [%s]", ctx.file_path, checksum))
    end
end

return M
