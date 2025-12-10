local hex = {}

function hex.toInt(hexstr)
    if type(hexstr) ~= "string" then
        error("hex_to_int expects a string, got " .. type(hexstr))
    end

    if string.sub(hexstr, 1, 2) == "0x" or string.sub(hexstr, 1, 2) == "0X" then
        return tonumber(hexstr)  -- Lua understands "0x.." prefix
    else
        return tonumber(hexstr, 16)
    end
end

-- Convert an integer to a hex string (like 26 -> "0x1A")
function hex.fromInt(num)
    return string.format("0x%X", num)
end

return hex
