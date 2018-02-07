local M = {}

local ngx = ngx

function M.start(params)
    local method = ngx.var.request_method
    if method ~= "POST" and method ~= "PUT" then
        ngx.exit(ngx.HTTP_NOT_ALLOWED) -- 405
    end

    ngx.log(ngx.INFO, "filename " .. params.filename)
    return ngx.OK
end

return M
