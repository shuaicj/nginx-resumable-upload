local M = {}

local io = io
local string = string
local tostring = tostring
local tonumber = tonumber
local ngx = ngx

local ffi = require "ffi"
local util = require "shuaicj.upload.util"

ffi.cdef[[
unsigned long crc32(unsigned long crc, const char *buf, unsigned len);
]]


M.header = "X-Checksum-CRC32"

function M.check_headers(ctx, headers)
    local v = headers[M.header]
    if v and #v == 8 and string.match(v, "^%x+$") then
        ctx.checksum.crc32 = {
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
    local f, e = io.open(ctx.file_path, "rb")
    if not f then
        ngx.log(ngx.ERR, e)
        return util.exit(500, e)
    end

    local checksum = 0
    while true do
        local data = f:read(4096)
        if not data then
            f:close()
            break
        end
        checksum = ffi.C.crc32(checksum, data, #data)
    end

    checksum = string.format("%08x", tonumber(checksum))
    ctx.checksum.crc32.server = checksum

    if ctx.checksum.crc32.client ~= checksum then
        util.truncate_file(ctx.file_path)
        ctx.real_size = 0
        local s = string.format("CRC32 conflict. file[%s] client [%s], server [%s]",
            ctx.file_path, ctx.checksum.crc32.client, checksum)
        ngx.log(ngx.ERR, s)
        return util.exit(409, s, ctx)
    else
        ngx.log(ngx.INFO, string.format("CRC32 match. file[%s] CRC32 [%s]", ctx.file_path, checksum))
    end
end

return M
