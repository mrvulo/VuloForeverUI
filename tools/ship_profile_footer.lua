ns.SHIPPED = SHIPPED

-- shipped wins over the code default; tables are walked, never replaced
local function overlay(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            overlay(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end
ns.ShippedOverlay = overlay

overlay(ns.defaults.global, SHIPPED.global or {})
overlay(ns.defaults.profile, SHIPPED.profile or {})

-- Called by ns:RegisterModule with the module's own defaults.
function ns.ApplyShipped(key, defaults)
    local m = SHIPPED.modules and SHIPPED.modules[key]
    if m then overlay(defaults, m) end
    defaults.enabled = not (SHIPPED.modulesOff and SHIPPED.modulesOff[key])
end
