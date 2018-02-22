local M = {}

local io = io
local math = math
local string = string
local table = table
local tostring = tostring
local ipairs = ipairs
local type = type
local error = error
local ngx = ngx

local util = require "shuaicj.upload.util"

function M.init(config)
    M.inited = false
    M.config = {}
    M.checksum_verifiers = {}

    if not config.directory then
        return error("no arg 'directory' found, check your nginx config")
    end
    if config.directory:sub(-1) == "/" then
        M.config.directory = config.directory
    else
        M.config.directory = config.directory .. "/"
    end

    if config.checksum then
        if type(config.checksum) == "string" then
            table.insert(M.checksum_verifiers, require("shuaicj.upload.checksum." .. config.checksum))
        else
            for _, v in ipairs(config.checksum) do
                table.insert(M.checksum_verifiers, require("shuaicj.upload.checksum." .. v))
            end
        end
    end

    if config.timeout and config.timeout <= 0 then
        return error(string.format("timeout [%d] illegal", config.timeout))
    end
    M.config.timeout = config.timeout or 20000

    M.inited = true
end

function M.upload(filename)
    local ctx = {}
    M.check_init()
    M.check_method(ctx, {"POST", "PUT"})
    M.check_filename(ctx, filename)
    M.check_headers(ctx, ngx.req.get_headers())

    if ctx.chunk_size > 0 and ctx.range_end == ctx.file_size - 1 then
        ctx.checksum = {}
        for _, verifier in ipairs(M.checksum_verifiers) do
            verifier.check_headers(ctx, ngx.req.get_headers())
        end
    end

    M.receive_and_write_file(ctx)

    if ctx.chunk_size > 0 and ctx.range_end == ctx.file_size - 1 then
        for _, verifier in ipairs(M.checksum_verifiers) do
            verifier.verify_checksum(ctx)
        end
    end

    util.exit(201, nil, ctx)
end

function M.size(filename)
    local ctx = {}
    M.check_init()
    M.check_method(ctx, {"GET"})
    M.check_filename(ctx, filename)

    local exists, size = util.file_exists_and_size(ctx.file_path)
    if exists then
        return util.exit(200, tostring(size))
    end
    return util.exit(404, "0")
end

function M.check_init()
    if not M.inited then
        local s = "module not inited, check your nginx config"
        ngx.log(ngx.ERR, s)
        return util.exit(500, s)
    end
end

function M.check_method(ctx, allow_methods)
    local method = ngx.var.request_method
    local method_ok
    for _, m in ipairs(allow_methods) do
        if m == method then
            method_ok = true
            break
        end
    end
    if not method_ok then
        return util.exit(405, string.format("method [%s] not allowed", method))
    end
    ctx.method = method
end

function M.check_filename(ctx, filename)
    if not filename then
        local s = "no arg 'filename' found, check your nginx config"
        ngx.log(ngx.ERR, s)
        return util.exit(500, s)
    end
    if not filename:match("^[a-zA-Z0-9-_.]+$") then
        local s = string.format("filename [%s] contains illegal characters", filename)
        ngx.log(ngx.WARN, s)
        return util.exit(400, s)
    end
    ctx.file_path = M.config.directory .. filename
end

function M.check_headers(ctx, headers)
    local chunk_size = tonumber(headers["Content-Length"])
    if not chunk_size or chunk_size < 0 then
        local s = "Content-Length missing or illegal"
        ngx.log(ngx.WARN, s)
        return util.exit(411, s)
    end

    local range_start, range_end, file_size
    if chunk_size == 0 then
        range_start = 0
        range_end = 0
        file_size = 0
    else
        local range = headers["Content-Range"]
        if not range then
            range_start = 0
            range_end = chunk_size - 1
            file_size = chunk_size
        else
            range_start, range_end, file_size = range:match("%s*bytes%s+(%d+)-(%d+)/(%d+)")
            local range_ok
            if range_start and range_end and file_size then
                range_start = tonumber(range_start)
                range_end = tonumber(range_end)
                file_size = tonumber(file_size)
                if range_start >= 0 and range_start <= range_end
                    and range_end < file_size and file_size > 0
                    and range_end - range_start + 1 == chunk_size then
                    range_ok = true
                end
            end
            if not range_ok then
                local s = string.format("Content-Range [%s] illegal", range)
                ngx.log(ngx.WARN, s)
                return util.exit(416, s)
            end
        end
    end

    ctx.range_start = range_start
    ctx.range_end = range_end
    ctx.file_size = file_size
    ctx.chunk_size = chunk_size
end

function M.receive_and_write_file(ctx)
    local exists, size = util.file_exists_and_size(ctx.file_path)
    ctx.real_size = size
    if ctx.range_start > size or ctx.file_size < size
        or ctx.method == "POST" and ctx.range_start ~= size then
        local s = string.format("range illegal, range_start %d, file_size %d, real_size %d",
            ctx.range_start, ctx.file_size, ctx.real_size)
        ngx.log(ngx.WARN, s)
        return util.exit(416, s, ctx)
    end

    local f, e
    if not exists then
        f, e = io.open(ctx.file_path, "wb")
    else
        f, e = io.open(ctx.file_path, "rb+")
    end
    if not f then
        ngx.log(ngx.ERR, e)
        return util.exit(500, e)
    end

    if exists then
        f:seek("set", ctx.range_start)
    end

    if ctx.chunk_size > 0 then
        local sock, e = ngx.req.socket()
        if not sock then
            f:close()
            ngx.log(ngx.ERR, e)
            return util.exit(500, e)
        end
        sock:settimeout(M.config.timeout)
        local remaining = ctx.chunk_size
        while remaining > 0 do
            local n = remaining < 4096 and remaining or 4096
            local data, e = sock:receive(n)
            if not data then
                f:close()
                ngx.log(ngx.ERR, e)
                return util.exit(500, e)
            end
            f:write(data)
            remaining = remaining - n
        end
        if ctx.range_end + 1 > ctx.real_size then
            ctx.real_size = ctx.range_end + 1
        end
    end

    f:close()
    ngx.log(ngx.INFO, string.format("write file ok. %s %d-%d/%d",
        ctx.file_path, ctx.range_start, ctx.range_end, ctx.file_size))
end

return M
