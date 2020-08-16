-- zone-related data and logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

require('dfhack.buildings') -- loads additional functions into dfhack.buildings
local utils = require('utils')
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_building = reqscript('internal/quickfort/building')
local log = quickfort_common.log

local function is_valid_zone_tile(pos)
    return not dfhack.maps.getTileFlags(pos).hidden
end

local function is_valid_zone_extent(s)
    for extent_x, col in ipairs(s.extent_grid) do
        for extent_y, in_extent in ipairs(col) do
            if in_extent then return true end
        end
    end
    return false
end

local zone_template = {
    has_extents=true, min_width=1, max_width=31, min_height=1, max_height=31,
    is_valid_tile_fn = is_valid_zone_tile,
    is_valid_extent_fn = is_valid_zone_extent
}

local zone_db = {
    a={label='Inactive', flags={'active'}}, -- unspecified means active
    w={label='Water Source', flags={'water_source'}},
    f={label='Fishing', flags={'fishing'}},
    g={label='Gather/Pick Fruit', flags={'gather'}},
    d={label='Garbage Dump', flags={'garbage_dump'}},
    n={label='Pen/Pasture', flags={'pen_pasture'}},
    p={label='Pit/Pond', flags={'pit_pond'}},
    s={label='Sand', flags={'sand'}},
    c={label='Clay', flags={'clay'}},
    m={label='Meeting Area', flags={'meeting_area'}},
    h={label='Hospital', flags={'hospital'}},
    t={label='Animal Training', flags={'animal_training'}},
}
for _, v in pairs(zone_db) do utils.assign(v, zone_template) end

local function custom_zone(_, keys)
    local labels = {}
    local flags = {}
    for k in keys:gmatch('.') do
        if not zone_db[k] then return nil end
        table.insert(labels, zone_db[k].label)
        table.insert(flags, zone_db[k].flags[1])
    end
    local zone_data = {label=table.concat(labels, '+'), flags=flags}
    utils.assign(zone_data, zone_template)
    return zone_data
end

setmetatable(zone_db, {__index=custom_zone})

local function create_zone(zone)
    log('creating %s zone at map coordinates (%d, %d, %d), defined' ..
        ' from spreadsheet cells: %s',
        zone_db[zone.type].label, zone.pos.x, zone.pos.y, zone.pos.z,
        table.concat(zone.cells, ', '))
    local extents, ntiles = quickfort_building.make_extents(zone, zone_db)
    local fields = {room={x=zone.pos.x, y=zone.pos.y,
                          width=zone.width, height=zone.height},
                    is_room=true}
    local bld, err = dfhack.buildings.constructBuilding{
        type=df.building_type.Civzone, subtype=df.civzone_type.ActivityZone,
        abstract=true, pos=zone.pos, width=zone.width, height=zone.height,
        fields=fields}
    if not bld then
        if extents then df.delete(extents) end
        -- this is an error instead of a qerror since our validity checking
        -- is supposed to prevent this from ever happening
        error(string.format('unable to designate zone: %s', err))
    end
    -- constructBuilding deallocates extents, so we have to assign it after
    bld.room.extents = extents
    for _,flag in ipairs(zone_db[zone.type].flags) do
        bld.zone_flags[flag] = true
    end
    -- zones are enabled by default. if it was toggled in the keys, we actually
    -- want to turn it off here
    bld.zone_flags.active = not bld.zone_flags.active
    bld.gather_flags.pick_trees = true
    bld.gather_flags.pick_shrubs = true
    bld.gather_flags.gather_fallen = true
    return ntiles
end

function do_run(zlevel, grid, ctx)
    local stats = ctx.stats
    stats.zone_designated = stats.zone_designated or
            {label='Zones designated', value=0, always=true}
    stats.zone_tiles = stats.zone_tiles or
            {label='Zone tiles designated', value=0}
    stats.zone_occupied = stats.zone_occupied or
            {label='Zone tiles skipped (tile occupied)', value=0}

    local zones = {}
    stats.invalid_keys.value =
            stats.invalid_keys.value + quickfort_building.init_buildings(
                zlevel, grid, zones, zone_db)
    stats.out_of_bounds.value =
            stats.out_of_bounds.value + quickfort_building.crop_to_bounds(
                zones, zone_db)
    stats.zone_occupied.value =
            stats.zone_occupied.value +
            quickfort_building.check_tiles_and_extents(
                zones, zone_db)

    for _,zone in ipairs(zones) do
        if zone.pos then
            local ntiles = create_zone(zone)
            stats.zone_tiles.value = stats.zone_tiles.value + ntiles
            stats.zone_designated.value = stats.zone_designated.value + 1
        end
    end
    dfhack.job.checkBuildingsNow()
end

function do_orders()
    log('nothing to do for blueprints in mode: zone')
end

local function get_activity_zones(pos)
    local activity_zones = {}
    local civzones = dfhack.buildings.findCivzonesAt(pos)
    if not civzones then return activity_zones end
    for _,civzone in ipairs(civzones) do
        if civzone.type == df.civzone_type.ActivityZone then
            table.insert(activity_zones, civzone)
        end
    end
    return activity_zones
end

function do_undo(zlevel, grid, ctx)
    local stats = ctx.stats
    stats.zone_removed = stats.zone_removed or
            {label='Zones removed', value=0, always=true}

    local zones = {}
    stats.invalid_keys.value =
            stats.invalid_keys.value + quickfort_building.init_buildings(
                zlevel, grid, zones, zone_db)

    -- ensure a zone is not currently selected when we delete it. that causes
    -- crashes. note that we move the cursor, but we have to keep the ui mode
    -- the same. otherwise the zone stays selected (somehow) in memory. we only
    -- move the cursor when we're in mode Zones to avoid having the viewport
    -- jump around when it doesn't need to
    local restore_cursor = false
    if df.global.ui.main.mode == df.ui_sidebar_mode.Zones then
        quickfort_common.move_cursor(xyz2pos(-1, -1, ctx.cursor.z))
        restore_cursor = true
    end

    for _, zone in ipairs(zones) do
        for extent_x, col in ipairs(zone.extent_grid) do
            for extent_y, in_extent in ipairs(col) do
                if not zone.extent_grid[extent_x][extent_y] then goto continue end
                local pos = xyz2pos(zone.pos.x+extent_x-1,
                                    zone.pos.y+extent_y-1, zone.pos.z)
                local activity_zones = get_activity_zones(pos)
                for _,activity_zone in ipairs(activity_zones) do
                    log('removing zone at map coordinates (%d, %d, %d)',
                        pos.x, pos.y, pos.z)
                    dfhack.buildings.deconstruct(activity_zone)
                    stats.zone_removed.value = stats.zone_removed.value + 1
                end
                ::continue::
            end
        end
    end

    if restore_cursor then quickfort_common.move_cursor(ctx.cursor) end
end
