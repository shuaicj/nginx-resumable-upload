local M = {}

local io = io
local string = string
local pairs = pairs
local ngx = ngx

function M.tohex(str)
    return (string.gsub(str, '.', function (c)
        return string.format('%02x', string.byte(c))
    end))
end

function M.exit(http_status_code, body, ctx)
    ngx.status = http_status_code
    if ctx then 
        if ctx.file_size and ctx.real_size and ctx.real_size > 0 then
            ngx.header["Content-Range"] = string.format("bytes 0-%d/%d",
                ctx.real_size - 1, ctx.file_size)
        end
        if ctx.checksum then
            for _, checksum in pairs(ctx.checksum) do
                if checksum.server then
                    ngx.header[checksum.header] = checksum.server
                end
            end
        end
    end
    if body then
        ngx.say(body)
    end
    return ngx.exit(ngx.OK)
end

function M.truncate_file(path)
    local f = io.open(path, "wb")
    if f then
        f:close()
    end
end

-- return exists[true|false], size[number]
function M.file_exists_and_size(path)
    local f = io.open(path, "rb")
    if f then
        local size = f:seek("end")
        f:close()
        return true, size
    end
    return false, 0
end

return M
