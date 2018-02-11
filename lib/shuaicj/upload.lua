local M = {}

local io = io
local math = math
local string = string
local tostring = tostring
local ipairs = ipairs
local ngx = ngx

function M.upload(args)
    M.check_args(args, {"POST", "PUT"})
    M.check_headers(ngx.req.get_headers())
    ngx.log(ngx.INFO, "filename " .. args.filename)
end

function M.size(args)
    M.check_args(args, {"GET"})
    local f = io.open(M.fullname(args), "rb")
    if f then
        local size = f:seek("end")
        f:close()
        return M.exit(200, tostring(size))
    end
    return M.exit(200, "0")
end

function M.check_args(args, allow_methods)
    local method = ngx.var.request_method
    local method_ok
    for _, m in ipairs(allow_methods) do
        if m == method then
            method_ok = true
            break
        end
    end
    if not method_ok then
        return M.exit(405, string.format("method [%s] not allowed", method))
    end
    if not args.dir then
        local s = "no arg 'dir' found, check your nginx config"
        ngx.log(ngx.ERR, s)
        return M.exit(500, s)
    end
    if not args.filename then
        local s = "no arg 'filename' found, check your nginx config"
        ngx.log(ngx.ERR, s)
        return M.exit(500, s)
    end
    if not args.filename:match("^[a-zA-Z0-9-_.]+$") then
        local s = string.format("filename [%s] contains illegal characters", args.filename)
        ngx.log(ngx.WARN, s)
        return M.exit(400, s)
    end
end

function M.check_headers()
    local headers = ngx.req.get_headers()
    local content_length = tonumber(headers["content-length"])
    if not content_length or content_length < 0 then
        local s = "Content-Length missing or illegal"
        ngx.log(ngx.WARN, s)
        return M.exit(411, s)
    end

    local content_range = headers["content-range"]
    local rg_from, rg_to, rg_total
    if not content_range then
        rg_from = 0
        rg_to = content_length - 1
        rg_total = content_length
    else
        rg_from, rg_to, rg_total = content_range:match("%s*bytes%s+(%d+)-(%d+)/(%d+)")
    end
    if not rg_from or not rg_to or not rg_total then
        local s = string.format("Content-Range [%s] illegal", content_range)
        ngx.log(ngx.WARN, s)
        return M.exit(416, s)
    end
    rg_from = tonumber(rg_from)
    rg_to = tonumber(rg_to)
    rg_total = tonumber(rg_total)
    else
    end
end

function M.fullname(args)
    if args.dir:sub(-1) == "/" then
        return args.dir .. args.filename
    end
    return args.dir .. "/" .. args.filename
end

function M.exit(http_status_code, body)
    ngx.status = http_status_code
    ngx.say(body)
    return ngx.exit(200)
end

return M
