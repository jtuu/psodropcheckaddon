local itemfile = "addons/DropChecker/items.txt"
local specialfile = "addons/DropChecker/specials.txt"
local techfile = "addons/DropChecker/techs.txt"
local itemlist = {}
local speciallist = {}
local techlist = {}

local AREA_PTR = 0x00AC9D58
local EPISODES = {
    [1] = {
        "Pioneer 2", "Forest 1", "Forest 2", "Caves 1", "Caves 2", "Caves 3",
        "Mines 1", "Mines 2", "Ruins 1", "Ruins 2", "Ruins 3",
        "Dragon", "De Rol Le", "Vol Opt", "Dark Falz",
        "Lobby", "Temple", "Spaceship"
    },
    [2] = {
        "Pioneer 2", "VR Temple Alpha", "VR Temple Beta", "VR Spaceship Alpha",
        "VR Spaceship Beta", "Central Control Area", "Jungle Area North",
        "Jungle Area East", "Mountain Area", "Seaside Area", "Seabed Upper Levels",
        "Seabed Lower Levels", "Gal Gryphon", "Olga Flow", "Barba Ray", "Gol Dragon",
        "Seaside Area", "Tower"
    },
    [4] = {
        "Pioneer 2", "Crater East", "Crater West", "Crater South", "Crater North",
        "Crater Interior", "Desert 1", "Desert 2", "Desert 3", "Saint Milion"
    }
}

local table_read_fallback = {
    __index = function(tbl, key)
        for k,v in pairs(tbl) do
            if key == k then
                return v
            end
        end
        return nil
    end
}

local ZONE_PTR = 0x00AC9CF4
local ZONES = {
    [0xa15ba8] = "Forest",
    [0xa15d5c] = "Caves",
    [0xa15df8] = "Mines",
    [0xa15c54] = "Ruins",

    [0xa15f40] = "Temple",
    [0xa15f0c] = "Spaceship",
    [0xa15e2c] = "CCA",
    [0xa15ed8] = "Seabed",

    [0xa15f74] = "Crater",
    [0xa16020] = "Crater interior",
    [0xa16054] = "Desert"
}
setmetatable(ZONES, table_read_fallback)

local ZONE_EPISODES = {
    ["Forest"] = 1,
    ["Caves"] = 1,
    ["Mines"] = 1,
    ["Ruins"] = 1,

    ["Temple"] = 2,
    ["Spaceship"] = 2,
    ["CCA"] = 2,
    ["Seabed"] = 2,

    ["Crater"] = 4,
    ["Crater interior"] = 4,
    ["Desert"] = 4
}
setmetatable(ZONE_EPISODES, table_read_fallback)

local function get_episode()
    return ZONE_EPISODES[ZONES[pso.read_u32(ZONE_PTR)]]
end

local function get_areaname()
    local ep = EPISODES[get_episode()]
    if not ep then return "Unknown" end
    return ep[area]
end

local function get_current_areaname()
    return get_areaname(pso.read_u8(AREA_PTR) + 1)
end

local function loadtable(file)
    local t = {}
    for line in io.lines(file) do
        local sp = {}
        for value, wep in string.gmatch(line, '(%w+) (.+)') do
            t[tonumber(value, 16)] = wep
        end
    end
    return t
end

local function init()
    itemlist = loadtable(itemfile)
    setmetatable(itemlist, table_read_fallback)
    techlist = loadtable(techfile)
    speciallist = loadtable(specialfile)
    return {
        name = "DropChecker",
        version = "r3",
        author = "jake"
    }
end

local DROPTABLE_PTR = 0x00A8D8A4
local ITEMSTEP = 0x24
local ITEMSIZE = 0xC
local AREASTEP = 0x1B00
local AREACOUNT = 17
local MAXITEMS = 150 -- is this even a thing?

local lastfloorscan = {}
local droplist = {}

local function array_to_string(t)
    local buf = "{ "
    for i,v in ipairs(t) do
        buf = buf .. tostring(v) .. ", "
    end
    return buf .. " }"
end

-- kinda ghetto, but good enough?
function arrays_eq(a, b)
    local acount = 0
    local bcount = 0
    for i,v in ipairs(a) do
        acount = acount + 1
    end
    for i,v in ipairs(b) do
        bcount = bcount + 1
    end

    if acount ~= bcount then
        return false
    end

    for i,v in ipairs(a) do
        if b[i] ~= v then
            return false
        end
    end
    return true
end

function index_eq(tbl, key)
    for k,v in pairs(tbl) do
        if arrays_eq(key, k) then
            return v
        end
    end
end

function newindex(tbl, key, value)
    for k,v in pairs(tbl) do
        if arrays_eq(key, k) then
            rawset(tbl, k, value)
            return
        end
    end
    rawset(tbl, key, value)
end

local function clear_table(t)
    local next = next
    local k = next(t)
    while k ~= nil do
        t[k] = nil
        k = next(t, k)
    end
end

local drops = {}
setmetatable(drops, {__index = index_eq, __newindex=newindex})
local function scanfloor()
    local floorptr = pso.read_u32(DROPTABLE_PTR) + 16
    if floorptr == 16 then
        return {}
    end

    clear_table(drops)

    for area = 0, AREACOUNT do
        for item = 0, MAXITEMS do
            local offset = floorptr + AREASTEP*area + ITEMSTEP*item

            local itemid = bit.rshift(bit.bswap(pso.read_u32(offset)), 8)
            if itemid == 0 then
                break
            end

            if itemlist[itemid] ~= nil then
                itembuf = {}
                pso.read_mem(itembuf, offset, ITEMSIZE)

                local value = 0
                for k,v in ipairs(itembuf) do
                    value = value + v
                end

                table.insert(drops, {
                    ["item"] = itembuf,
                    ["area"] = area,
                    ["value"] = value})
            end
        end
    end

    return drops
end


local function wepstring(item)
    local wepid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]

    local native = 0
    local abeast = 0
    local machine = 0
    local dark = 0
    local hit = 0

    for i = 0, 2 do
        if item[7+i*2] == 1 then
            native = item[8+i*2]
        end
        if item[7+i*2] == 2 then
            abeast = item[8+i*2]
        end
        if item[7+i*2] == 3 then
            machine = item[8+i*2]
        end
        if item[7+i*2] == 4 then
            dark = item[8+i*2]
        end
        if item[7+i*2] == 5 then
            hit = item[8+i*2]
        end
    end

    local result = ""
    if bit.band(item[5], 0x3F) ~= 0 then
        result = result .. speciallist[bit.band(item[5], 0x3F)] .. " "
    end

    result = result .. itemlist[wepid]

    if item[4] ~= 0 then
        result = result .. " +" .. tostring(item[4])
    end

    result = result .. string.format(" %d/%d/%d/%d|%d", native, abeast, machine, dark, hit)

    return result
end

local function armorstring(item)
    local armorid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    local slots = item[6]
    local dfp = item[7]
    local evp = item[9]

    return string.format("%s [%ds +%dd +%de]", itemlist[armorid], slots, dfp, evp)
end


local function shieldstring(item)
    local shieldid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    local dfp = item[7]
    local evp = item[9]

    return string.format("%s [+%dd +%de]", itemlist[shieldid], dfp, evp)
end

local function miscstring(item)
    local miscid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]

    if item[6] > 0 then
        return string.format("%s x%d", itemlist[miscid], item[6])
    end
    return itemlist[miscid]
end

-- TODO!
local function magstring(item)
    local magid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    return itemlist[magid]
end

local function techstring(item)
    local level = item[1]+1
    local techid = item[5]

    return string.format("%s %d", techlist[techid], level)
end

local function itemtostring(item)
    if item[1] == 0x00 then
        return wepstring(item)
    elseif item[1] == 0x01 then
        if item[2] == 0x01 then
            return armorstring(item)
        elseif item[2] == 0x02 then
            return shieldstring(item)
        elseif item[2] == 0x03 then
            return miscstring(item)
        end
    elseif item[1] == 0x02 then
        return magstring(item)
    elseif item[1] == 0x03 then
        if item[2] == 0x02 then
            return techstring(item)
        else
            return miscstring(item)
        end
    end
end

local droplist_compare = function(a, b)
    if a.area == b.area then
        return a.value > b.value
    else return a.area > b.area end
end

local prevmaxy = 0
local UPDATE_INTERVAL = 20
local itercount = UPDATE_INTERVAL - 1

local prev_area = ""
local cur_area = ""
local collapsible_states = {}

local present = function()
    itercount = itercount + 1

    imgui.Begin("Drop Checker")

    local sy = imgui.GetScrollY()
    local sym = imgui.GetScrollMaxY()
    scrolldown = false
    if imgui.GetScrollY() <= 0 or prevmaxy == imgui.GetScrollY() then
        scrolldown = true
    end

    -- dont need to do this every frame
    if itercount % UPDATE_INTERVAL == 0 then
        droplist = scanfloor()
        -- unsure if this actually speeds anything up
        while #droplist > 100 do
            table.remove(droplist, 1)
        end

        table.sort(droplist, droplist_compare)
        cur_area = get_current_areaname()

        -- cache the stringified item and area
        for i,drop in ipairs(droplist) do
            drop.itemstr = itemtostring(drop.item)
            drop.areastr = get_areaname(drop.area + 1)
        end

        itercount = 0
    end

    -- player changed areas, open/close menus
    if prev_area ~= cur_area then
        clear_table(collapsible_states)
        prev_area = cur_area
    end

    for i,drop in ipairs(droplist) do -- iterate through drops
        local itemstr = drop.itemstr
        if itemstr ~= nil then
            local area = drop.areastr
            local prev = droplist[i - 1]
            -- if item is in a different area than the previous one,
            -- add a CollapsingHeader
            if area ~= prev.area then
                -- set header to open if it has been clicked open or it is the current area
                -- (this means current area menu can't be closed atm)
                imgui.SetNextTreeNodeOpen(collapsible_states[area] == true or area == cur_area)
                -- save the open state
                local is_open = imgui.CollapsingHeader(area)
                collapsible_states[area] = is_open
                -- add the text if the menu is open
                if is_open then imgui.Text(itemstr) end
            elseif area == cur_area then -- item is in same area as the previous one, continue drawing here
                imgui.Text(itemstr)
            end
        end
    end

    if scrolldown then
        imgui.SetScrollY(imgui.GetScrollMaxY())
    end

    prevmaxy = imgui.GetScrollMaxY()
    imgui.End()
end

pso.on_init(init)
pso.on_present(present)

return {
    init = init,
    present = present
}
