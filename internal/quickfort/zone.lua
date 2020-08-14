-- zone-related data and logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

require('dfhack.buildings') -- loads additional functions into dfhack.buildings
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_building = reqscript('internal/quickfort/building')
local quickfort_place = reqscript('internal/quickfort/place')
local log = quickfort_common.log

local zone_db = {
    w={label='Water Source', flag='water_source'},
    f={label='Fishing', flag='fishing'},
    g={label='Gather/Pick Fruit', flag='gather'},
    d={label='Garbage Dump', flag='garbage_dump'},
    n={label='Pen/Pasture', flag='pen_pasture'},
    p={label='Pit/Pond', flag='pit_pond'},
    s={label='Sand', flag='sand'},
    c={label='Clay', flag='clay'},
    m={label='Meeting Area', flag='meeting_area'},
    h={label='Hospital', flag='hospital'},
    t={label='Animal Training', flag='animal_training'},
}
for _, v in pairs(zone_db) do
    v.has_extents = true
    v.min_width = 1
    v.max_width = 31
    v.min_height = 1
    v.max_height = 31
    v.is_valid_tile_fn = quickfort_place.is_valid_stockpile_tile
    v.is_valid_extent_fn = quickfort_place.is_valid_stockpile_extent
end

local function create_zone(zone)
    log('creating %s zone at map coordinates (%d, %d, %d), defined' ..
        ' from spreadsheet cells: %s',
        zone_db[zone.type].label, zone.pos.x, zone.pos.y, zone.pos.z,
        table.concat(zone.cells, ', '))
    local extents, ntiles = quickfort_building.make_extents(zone, zone_db)
    local fields = {room={x=zone.pos.x, y=zone.pos.y,
                          width=zone.width, height=zone.height}}
    local bld, err = dfhack.buildings.constructBuilding{
        type=df.building_type.Civzone, subtype=df.civzone_type.ActivityZone,
        abstract=true, pos=zone.pos, width=zone.width, height=zone.height,
        fields=fields}
    if not bld then
        if extents then df.delete(extents) end
        -- this is an error instead of a qerror since our validity checking
        -- is supposed to prevent this from ever happening
        error(string.format('unable to place stockpile: %s', err))
    end
    -- constructBuilding deallocates extents, so we have to assign it after
    bld.room.extents = extents
    bld.zone_flags[zone_db[zone.type].flag] = true
    return ntiles
end

function do_run(zlevel, grid)
    local stats = {
        zones_designated={label='Zones designated', value=0, always=true},
        tiles_designated={label='Tiles designated', value=0},
        occupied={label='Tiles skipped (tile occupied)', value=0},
        out_of_bounds={label='Tiles skipped (outside map boundary)', value=0},
        invalid_keys={label='Invalid key sequences', value=0},
    }

    local zones = {}
    stats.invalid_keys.value = quickfort_building.init_buildings(
        zlevel, grid, zones, zone_db)
    stats.out_of_bounds.value = quickfort_building.crop_to_bounds(
        zones, zone_db)
    stats.occupied.value = quickfort_building.check_tiles_and_extents(
        zones, zone_db)

    for _,zone in ipairs(zones) do
        if zone.pos then
            local ntiles = create_zone(zone)
            stats.tiles_designated.value = stats.tiles_designated.value + ntiles
            stats.zones_designated.value = stats.zones_designated.value + 1
        end
    end
    dfhack.job.checkBuildingsNow()
    return stats
end

function do_orders(zlevel, grid)
    log('nothing to do for blueprints in mode: zone')
    return nil
end

function do_undo(zlevel, grid)
    local stats = {
        zones_removed={label='Zones removed', value=0, always=true},
        invalid_keys={label='Invalid key sequences', value=0},
    }

    local zones = {}
    stats.invalid_keys.value = quickfort_building.init_buildings(
        zlevel, grid, zones, zone_db)

    for _, zone in ipairs(zones) do
        for extent_x, col in ipairs(zone.extent_grid) do
            for extent_y, in_extent in ipairs(col) do
                if not zone.extent_grid[extent_x][extent_y] then goto continue end
                local pos = xyz2pos(zone.pos.x+extent_x-1,
                                    zone.pos.y+extent_y-1, zone.pos.z)
                local civzones = dfhack.buildings.findCivzonesAt(pos)
                for _,civzone in ipairs(civzones) do
                    if civzone.type == df.civzone_type.ActivityZone then
                        dfhack.buildings.deconstruct(civzone)
                        stats.zones_removed.value = stats.zones_removed.value+1
                    end
                end
                ::continue::
            end
        end
    end
    return stats
end
