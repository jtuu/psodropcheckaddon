local itemfile = "addons/psodropcheckaddon/items.txt"
local specialfile = "addons/psodropcheckaddon/specials.txt"
local techfile = "addons/psodropcheckaddon/techs.txt"
local itemlist = {}
local speciallist = {}
local techlist = {}

local EPISODE_PTR = 0x00A9B1C8
local AREA_PTR = 0x00AC9D58
local EPISODES = {
    [0] = {
        "Pioneer 2", "Forest 1", "Forest 2", "Caves 1", "Caves 2", "Caves 3",
        "Mines 1", "Mines 2", "Ruins 1", "Ruins 2", "Ruins 3",
        "Dragon", "De Rol Le", "Vol Opt", "Dark Falz",
        "Lobby", "Temple", "Spaceship"
    },
    [1] = {
        "Pioneer 2", "VR Temple Alpha", "VR Temple Beta", "VR Spaceship Alpha",
        "VR Spaceship Beta", "Central Control Area", "Jungle Area North",
        "Jungle Area East", "Mountain Area", "Seaside Area", "Seabed Upper Levels",
        "Seabed Lower Levels", "Gal Gryphon", "Olga Flow", "Barba Ray", "Gol Dragon",
        "Seaside Area", "Tower"
    },
    [2] = {
        "Pioneer 2", "Crater East", "Crater West", "Crater South", "Crater North",
        "Crater Interior", "Desert 1", "Desert 2", "Desert 3", "Saint Milion"
    }
}

local function scalergb(rgb)
    local scaled = {}
    for k,v in ipairs(rgb) do
        table.insert(scaled, v / 255)
    end
    return scaled
end

local ITEMTYPE = {
    WEAPON = 0,
    ARMOR = 1,
    SHIELD = 2,
    UNIT = 3,
    MAG = 4,
    TECH = 5,
    CONSUMABLE = 6,
    MISC = 7,
    RARE = 8
}
local COLOR = {
    ORANGE = scalergb({255, 131, 50, 255}),
    BLUE = scalergb({48, 111, 179, 255}),
    GREEN = scalergb({45, 144, 27, 255}),
    RED = scalergb({255, 0, 0, 255})
}
local ITEMCOLOR = {
    [ITEMTYPE.WEAPON] = COLOR.ORANGE,
    [ITEMTYPE.ARMOR] = COLOR.BLUE,
    [ITEMTYPE.SHIELD] = COLOR.BLUE,
    [ITEMTYPE.UNIT] = COLOR.BLUE,
    [ITEMTYPE.MAG] = COLOR.BLUE,
    [ITEMTYPE.TECH] = COLOR.GREEN,
    [ITEMTYPE.CONSUMABLE] = COLOR.GREEN,
    [ITEMTYPE.MISC] = COLOR.GREEN,
    [ITEMTYPE.RARE] = COLOR.RED
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

local function get_episode()
    return pso.read_u8(EPISODE_PTR)
end

local function get_areaname(area)
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
        local parsed = {}
        for part in string.gmatch(line, "[^,]+") do
            table.insert(parsed, part)
        end
        local o = {name = parsed[2]}
        if parsed[3] ~= nil then
            o.rare = tonumber(parsed[3]) == 1
        else
            o.rare = false
        end
        t[tonumber(parsed[1], 16)] = o
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
                local itembuf = {}
                pso.read_mem(itembuf, offset, ITEMSIZE)
                table.insert(drops, {
                    item = itembuf,
                    area = area,
                    offset = offset,
                    rare = itemlist[itemid].rare
                })
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
        result = result .. speciallist[bit.band(item[5], 0x3F)].name .. " "
    end

    result = result .. itemlist[wepid].name

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

    return string.format("%s [%ds +%dd +%de]", itemlist[armorid].name, slots, dfp, evp)
end


local function shieldstring(item)
    local shieldid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    local dfp = item[7]
    local evp = item[9]

    return string.format("%s [+%dd +%de]", itemlist[shieldid].name, dfp, evp)
end

local function miscstring(item)
    local miscid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]

    if item[6] > 0 then
        return string.format("%s x%d", itemlist[miscid].name, item[6])
    end
    return itemlist[miscid].name
end

-- TODO!
local function magstring(item)
    local magid = item[1] * math.pow(2, 16) + item[2] * math.pow(2, 8) + item[3]
    return itemlist[magid].name
end

local function techstring(item)
    local level = item[3] + 1
    local techid = item[5]

    return string.format("%s %d", techlist[techid].name, level)
end

local function itemtostring(item, type)
    if     type == ITEMTYPE.WEAPON then return wepstring(item)
    elseif type == ITEMTYPE.ARMOR then return armorstring(item)
    elseif type == ITEMTYPE.SHIELD then return shieldstring(item)
    elseif type == ITEMTYPE.UNIT then return miscstring(item)
    elseif type == ITEMTYPE.MAG then return magstring(item)
    elseif type == ITEMTYPE.TECH then return techstring(item)
    elseif type == ITEMTYPE.CONSUMABLE then return miscstring(item)
    elseif type == ITEMTYPE.MISC then return miscstring(item)
    end
end

local function get_itemtype(item)
    if item[1] == 0x00 then
        return ITEMTYPE.WEAPON
    elseif item[1] == 0x01 then
        if item[2] == 0x01 then
            return ITEMTYPE.ARMOR
        elseif item[2] == 0x02 then
            return ITEMTYPE.SHIELD
        elseif item[2] == 0x03 then
            return ITEMTYPE.UNIT
        end
    elseif item[1] == 0x02 then
        return ITEMTYPE.MAG
    elseif item[1] == 0x03 then
        if item[2] == 0x02 then
            return ITEMTYPE.TECH
        elseif item[2] < 0x0c then
            return ITEMTYPE.CONSUMABLE
        else
            return ITEMTYPE.MISC
        end
    end
end

local droplist_compare = function(a, b)
    if a.area == b.area then
        if a.item[1] == b.item[1] then
            return a.item[2] < b.item[2]
        else return a.item[1] < b.item[1] end
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
            drop.type = get_itemtype(drop.item)
            drop.itemstr = itemtostring(drop.item, drop.type)
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
        if drop.itemstr ~= nil then
            local prev = i > 1 and droplist[i - 1] or {}
            -- if item is in a different area than the previous one,
            -- add a CollapsingHeader
            if drop.areastr ~= prev.areastr then
                -- set header to open if it has been clicked open or it is the current area
                -- (this means current area menu can't be closed atm)
                imgui.SetNextTreeNodeOpen(collapsible_states[drop.areastr] == true or drop.areastr == cur_area)
                -- save the open state
                local is_open = imgui.CollapsingHeader(drop.areastr)
                collapsible_states[drop.areastr] = is_open
            end

            -- if menu is open, draw the items inside it
            if collapsible_states[drop.areastr] == true then
                -- prefer rare coloring over the items natural type color
                local color = drop.rare and ITEMCOLOR[ITEMTYPE.RARE] or ITEMCOLOR[drop.type]
                imgui.TextColored(color[1], color[2], color[3], color[4], drop.itemstr)
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
