-- place-related data and logic for the quickfort script
--@ module = true
--[[
stockpiles data structure:
  list of {type, cells, pos, width, height, extent_grid}
- type: letter from stockpile designation screen
- cells: list of source spreadsheet cell labels (for debugging)
- pos: target map coordinates of upper left corner of extent (or nil if invalid)
- width, height: number between 1 and 31 (could be 0 if pos == nil)
- extent_grid: [x][y] -> boolean where 1 <= x <= width and 1 <= y <= height
]]

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

require('dfhack.buildings') -- loads additional functions into dfhack.buildings
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_building = reqscript('internal/quickfort/building')
local quickfort_query = reqscript('internal/quickfort/query')
local log = quickfort_common.log

function is_valid_stockpile_tile(pos)
    local flags, occupancy = dfhack.maps.getTileFlags(pos)
    if flags.hidden or occupancy.building ~= 0 then return false end
    local shape = df.tiletype.attrs[dfhack.maps.getTileType(pos)].shape
    return shape == df.tiletype_shape.FLOOR or
            shape == df.tiletype_shape.BOULDER or
            shape == df.tiletype_shape.PEBBLES or
            shape == df.tiletype_shape.STAIR_UP or
            shape == df.tiletype_shape.STAIR_DOWN or
            shape == df.tiletype_shape.STAIR_UPDOWN or
            shape == df.tiletype_shape.RAMP or
            shape == df.tiletype_shape.TWIG or
            shape == df.tiletype_shape.SAPLING or
            shape == df.tiletype_shape.SHRUB
end

function is_valid_stockpile_extent(s)
    for extent_x, col in ipairs(s.extent_grid) do
        for extent_y, in_extent in ipairs(col) do
            if in_extent then return true end
        end
    end
    return false
end

local stockpile_db = {
    a={label='Animal', index=0},
    f={label='Food', index=1, want_barrels=true},
    u={label='Furniture', index=2},
    n={label='Coins', index=7, want_bins=true},
    y={label='Corpses', index=3},
    r={label='Refuse', index=4},
    s={label='Stone', index=5, want_wheelbarrows=true},
    w={label='Wood', index=13},
    e={label='Gem', index=9, want_bins=true},
    b={label='Bar/Block', index=8, want_bins=true},
    h={label='Cloth', index=12, want_bins=true},
    l={label='Leather', index=11, want_bins=true},
    z={label='Ammo', index=6, want_bins=true},
    S={label='Sheets', index=16, want_bins=true},
    g={label='Finished Goods', index=10, want_bins=true},
    p={label='Weapons', index=14, want_bins=true},
    d={label='Armor', index=15, want_bins=true},
}
for _, v in pairs(stockpile_db) do
    v.has_extents = true
    v.min_width = 1
    v.max_width = 31
    v.min_height = 1
    v.max_height = 31
    v.is_valid_tile_fn = is_valid_stockpile_tile
    v.is_valid_extent_fn = is_valid_stockpile_extent
end

local function init_stockpile_settings(zlevel, stockpile_query_grid)
    local saved_verbosity = quickfort_common.verbose
    quickfort_common.verbose = false
    quickfort_query.do_run(zlevel, stockpile_query_grid)
    quickfort_common.verbose = saved_verbosity
end

local function get_stockpile_query_text(stockpile_type)
    return string.format('s{Down %d}e^', stockpile_db[stockpile_type].index)
end

local function queue_stockpile_settings_init(s, stockpile_query_grid)
    local query_x, query_y
    for extent_x, col in ipairs(s.extent_grid) do
        for extent_y, in_extent in ipairs(col) do
            if in_extent then
                query_x = s.pos.x + extent_x - 1
                query_y = s.pos.y + extent_y - 1
                break
            end
        end
        if active_x then break end
    end
    if not stockpile_query_grid[query_y] then
        stockpile_query_grid[query_y] = {}
    end
    stockpile_query_grid[query_y][query_x] =
            {cell='generated',text=get_stockpile_query_text(s.type)}
end

local function init_containers(db_entry, ntiles, fields)
    if db_entry.want_barrels then
        local max_barrels =
                quickfort_common.settings['stockpiles_max_barrels'].value
        if max_barrels < 0 or max_barrels >= ntiles then
            fields.max_barrels = ntiles
        else
            fields.max_barrels = max_barrels
        end
    end
    if db_entry.want_bins then
        local max_bins = quickfort_common.settings['stockpiles_max_bins'].value
        if max_bins < 0 or max_bins >= ntiles then
            fields.max_bins = ntiles
        else
            fields.max_bins = max_bins
        end
    end
    if db_entry.want_wheelbarrows then
        local max_wb =
                quickfort_common.settings['stockpiles_max_wheelbarrows'].value
        if max_wb < 0 then
            fields.max_wheelbarrows = 1
        elseif max_wb >= ntiles then
            fields.max_wheelbarrows = ntiles
        else
            fields.max_wheelbarrows = max_wb
        end
    end
end

local function create_stockpile(s, stockpile_query_grid)
    log('creating %s stockpile at map coordinates (%d, %d, %d), defined' ..
        ' from spreadsheet cells: %s',
        stockpile_db[s.type].label, s.pos.x, s.pos.y, s.pos.z,
        table.concat(s.cells, ', '))
    local extents, ntiles = quickfort_building.make_extents(s, stockpile_db)
    local fields = {room={x=s.pos.x, y=s.pos.y, width=s.width, height=s.height}}
    init_containers(stockpile_db[s.type], ntiles, fields)
    local bld, err = dfhack.buildings.constructBuilding{
        type=df.building_type.Stockpile, abstract=true, pos=s.pos,
        width=s.width, height=s.height, fields=fields}
    if not bld then
        if extents then df.delete(extents) end
        -- this is an error instead of a qerror since our validity checking
        -- is supposed to prevent this from ever happening
        error(string.format('unable to place stockpile: %s', err))
    end
    -- constructBuilding deallocates extents, so we have to assign it after
    bld.room.extents = extents
    queue_stockpile_settings_init(s, stockpile_query_grid)
    return ntiles
end

function do_run(zlevel, grid)
    local stats = {
        piles_designated={label='Stockpiles designated', value=0, always=true},
        tiles_designated={label='Tiles designated', value=0},
        occupied={label='Tiles skipped (tile occupied)', value=0},
        out_of_bounds={label='Tiles skipped (outside map boundary)', value=0},
        invalid_keys={label='Invalid key sequences', value=0},
    }

    local stockpiles = {}
    stats.invalid_keys.value = quickfort_building.init_buildings(
        zlevel, grid, stockpiles, stockpile_db)
    stats.out_of_bounds.value = quickfort_building.crop_to_bounds(
        stockpiles, stockpile_db)
    stats.occupied.value = quickfort_building.check_tiles_and_extents(
        stockpiles, stockpile_db)

    local stockpile_query_grid = {}
    for _, s in ipairs(stockpiles) do
        if s.pos then
            local ntiles = create_stockpile(s, stockpile_query_grid)
            stats.tiles_designated.value = stats.tiles_designated.value + ntiles
            stats.piles_designated.value = stats.piles_designated.value + 1
        end
    end
    init_stockpile_settings(zlevel, stockpile_query_grid)
    dfhack.job.checkBuildingsNow()
    return stats
end

function do_orders(zlevel, grid)
    log('nothing to do for blueprints in mode: place')
    return nil
end

function do_undo(zlevel, grid)
    local stats = {
        piles_removed={label='Stockpiles removed', value=0, always=true},
        invalid_keys={label='Invalid key sequences', value=0},
    }

    local stockpiles = {}
    stats.invalid_keys.value = quickfort_building.init_buildings(
        zlevel, grid, stockpiles, stockpile_db)

    for _, s in ipairs(stockpiles) do
        for extent_x, col in ipairs(s.extent_grid) do
            for extent_y, in_extent in ipairs(col) do
                if not s.extent_grid[extent_x][extent_y] then goto continue end
                local pos =
                        xyz2pos(s.pos.x+extent_x-1, s.pos.y+extent_y-1, s.pos.z)
                local bld = dfhack.buildings.findAtTile(pos)
                if bld and bld:getType() == df.building_type.Stockpile then
                    dfhack.buildings.deconstruct(bld)
                    stats.piles_removed.value = stats.piles_removed.value + 1
                end
                ::continue::
            end
        end
    end
    return stats
end
