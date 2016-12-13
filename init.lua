
local itemfile = "addons/DropChecker/items.txt"
local specialfile = "addons/DropChecker/specials.txt"
local techfile = "addons/DropChecker/techs.txt"
local itemlist = {}
local speciallist = {}
local techlist = {}

local areaptr = 0x00AC9D58

local episodes = {
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
        return 0
    end
}

local mapptr = 0x00AC9CF4
local mapvals = {
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
setmetatable(mapvals, table_read_fallback)

local episodemaps = {
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
setmetatable(episodemaps, table_read_fallback)


local get_episode = function()
    return episodemaps[mapvals[pso.read_u32(mapptr)]]
end

local get_areaname = function(area)
    local ep = episodes[get_episode()]

    if not ep then
        return "Unknown"
    end

    return ep[area]
end

local get_current_areaname = function()
    return get_areaname(pso.read_u8(areaptr) + 1)
end

local function loadtable(file)
    local t = {}
    for line in io.lines(file) do
        local sp = {}
        for value, wep in string.gmatch(line, '(%w+) (.+)') do
            --print(tonumber(value, 16))
            t[tonumber(value, 16)] = wep
        end
    end
    return t
end



local init = function()
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

function difference(a, b)
    local result = {}
    for k,v in pairs(a) do
        if b[k] ~= nil then
            local count = b[k]
            while v > count do
                table.insert(result, k)
                count = count + 1
            end
        else
            table.insert(result, k)
        end
    end
    return result
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

    --imgui.Text(string.format("pointer: 0x%x", floorptr))

    clear_table(drops)

    for area = 0, AREACOUNT do
        for item = 0, MAXITEMS do
            local offset = floorptr + AREASTEP*area + ITEMSTEP*item

            local itemid = bit.rshift(bit.bswap(pso.read_u32(offset)), 8)
            if itemid == 0 then
                break
            end
            print(string.format("itemid: %.6X %d", itemid, itemid))
            --imgui.Text(string.format("iid: 0x%X", itemid))
            --imgui.Text(string.format("?: %X %s", wep, itemlist[wep]))
            if itemlist[itemid] ~= nil then
                --drops.insert(itemlist[wep])
                itembuf = {}
                --setmetatable(itembuf, ITEMCMPMETA)
                pso.read_mem(itembuf, offset, ITEMSIZE)
                --imgui.Text("b: " .. tostring(array_to_string(itembuf)))
                print(tostring(array_to_string(itembuf)))
                table.insert(drops, {["item"] = itembuf, ["area"] = area, ["offset"] = offset})
                --print(string.format("%d %d"))
            end
        end
    end

    --print(#drops)
    --print(printtable(drops, nil))
    --print(#lastfloorscan)
    -- print(#diff)
    --print(printtable(diff, nil))
    --print("---")
    -- diff = difference(drops, lastfloorscan)
    -- lastfloorscan = drops

    return drops
end


local function wepstring(item)
    local wepid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    --imgui.Text(string.format("wid: 0x%X", wepid))

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
    --print("item: " .. tostring(array_to_string(item)))
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

    return a.area > b.area
end

local collapsible_states = {}

local prevmaxy = 0
local itercount = 0
local present = function()
    imgui.Begin("Drop Checker")

    local sy = imgui.GetScrollY()
    local sym = imgui.GetScrollMaxY()
    scrolldown = false
    if imgui.GetScrollY() <= 0 or prevmaxy == imgui.GetScrollY() then
        scrolldown = true
    end

    -- dont need to do this every frame
    if itercount % 20 == 0 then
        droplist = scanfloor()
        -- unsure if this actually speeds anything up
        while #droplist > 100 do
            table.remove(droplist, 1)
        end

        table.sort(droplist, droplist_compare)
    end

    itercount = itercount + 1

    local prev_area = ""
    local cur_area = get_current_areaname()
    for i,drop in ipairs(droplist) do
        local istr = itemtostring(drop.item)
        if istr ~= nil then
            local area = get_areaname(drop.area + 1)
            if area ~= prev_area then
                imgui.SetNextTreeNodeOpen(collapsible_states[area] or area == cur_area)
                local is_open = imgui.CollapsingHeader(area)
                collapsible_states[area] = is_open
                if is_open then
                    imgui.TextWrapped(istr)
                end
                prev_area = area
            elseif area == cur_area then
                imgui.TextWrapped(istr)
                prev_area = area
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
--pso.on_key_pressed(key_pressed)
--pso.on_key_released(key_released)

-- This isn't necessary, but may be useful if you want to use another addons'
-- code; you can retrieve an addon's module with require('AddonName').
return {
    init = init,
    present = present,
--key_pressed = key_pressed
}
