local M = {}

local string = string

function M.tohex(str)
    return (string.gsub(str, '.', function (c)
        return string.format('%02x', string.byte(c))
    end))
end

return M
