-- generates manager orders for the quickfort script
--@ module = true
--[[
Enqueues manager orders to produce the materials required to build the buildings
in a specified blueprint.
]]

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local stockflow = require('plugins.stockflow')
local quickfort_common = reqscript('internal/quickfort/common')
local log = quickfort_common.log

--
local function inc_order_spec(order_specs, filter, reactions, label)
    if label == 'wood' then
        log('no manager order for wood; go chop some!')
        return
    end
    local quantity = filter.quantity or 1
    label = label:gsub('_', ' ')
    log('needs: %d %s', quantity, label)
    if not order_specs[label] then
        local order = nil
        for _,v in ipairs(reactions) do
            local name = v.name:lower()
            if name:find('^'..label..'$') or
                    name:find('^construct rock '..label..'$') or
                    name:find('^make wooden '..label..'$') or
                    name:find('^make '..label..'$') or
                    name:find('^construct '..label..'$') or
                    name:find('^forge '..label..'$') or
                    name:find('^smelt '..label..'$') then
                order = v.order
                break
            end
        end
        if not order then error(string.format('unhandled label: %s', label)) end
        order_specs[label] = {order=order, quantity=0}
    end
    order_specs[label].quantity = order_specs[label].quantity + quantity
end

local function process_filter(order_specs, filter, reactions)
    local label = nil
    if filter.flags2 and filter.flags2.building_material then
        if filter.flags2.magma_safe then
            -- restrict this to magma-safe materials
            label = 'blocks'
        elseif filter.flags2.fire_safe then
            -- restrict this to fire-safe materials
            label = 'blocks'
        else label = 'blocks' end
    elseif filter.item_type == df.item_type.TOOL then
        label = df.tool_uses[filter.has_tool_use]:lower()
    elseif filter.item_type == df.item_type.ANIMALTRAP then
        label = 'animal trap'
    elseif filter.item_type == df.item_type.ARMORSTAND then
        label = 'armor stand'
    elseif filter.item_type == df.item_type.ANVIL then label = 'iron anvil'
    elseif filter.item_type == df.item_type.BALLISTAPARTS then
        label = 'ballista parts'
    elseif filter.item_type == df.item_type.BAR then label = 'magnetite ore'
    elseif filter.item_type == df.item_type.BOX then label = 'coffer'
    elseif filter.item_type == df.item_type.CATAPULTPARTS then
        label = 'catapult parts'
    elseif filter.item_type == df.item_type.CHAIN then label = 'cloth rope'
    elseif filter.item_type == df.item_type.CHAIR then label = 'throne'
    elseif filter.item_type == df.item_type.SMALLGEM then
        label = 'cut green glass'
    elseif filter.item_type == df.item_type.TRAPCOMP then
        label = 'enormous wooden corkscrew'
    elseif filter.item_type == df.item_type.TRAPPARTS then label = 'mechanisms'
    elseif filter.item_type == df.item_type.WEAPONRACK then
        label = 'weapon rack'
    elseif filter.item_type == df.item_type.WINDOW then
        label = 'green glass window'
    elseif filter.item_type then label = df.item_type[filter.item_type]:lower()
    elseif filter.vector_id == df.job_item_vector_id.ANY_WEAPON then
        label = 'iron battle axe'
    elseif filter.vector_id == df.job_item_vector_id.ANY_SPIKE then
        label = 'iron spear'
    end
    if not label then
        print('unhandled filter:')
        printall_recurse(filter)
        error('unhandled filter')
    end
    inc_order_spec(order_specs, filter, reactions, label)
end

-- returns the number of materials required for this extent-based structure
local function get_num_items(b)
    local num_tiles = 0
    for extent_x, col in ipairs(b.extent_grid) do
        for extent_y, in_extent in ipairs(col) do
            if in_extent then num_tiles = num_tiles + 1 end
        end
    end
    return math.floor(num_tiles/4) + 1
end

function enqueue_orders(stats, buildings, building_db)
    local order_specs = {}
    local reactions = stockflow.reaction_list -- don't cache this; it can reset
    for _, b in ipairs(buildings) do
        local db_entry = building_db[b.type]
        log('processing %s, defined from spreadsheet cell(s): %s',
            db_entry.label, table.concat(b.cells, ', '))
        local filters = dfhack.buildings.getFiltersByType(
            {}, db_entry.type, db_entry.subtype, db_entry.custom)
        if not filters then
            error(string.format(
                    'unhandled building type: "%s:%s:%s"; buildings.lua ' ..
                    'needs updating',
                    db_entry.type, db_entry.subtype, db_entry.custom))
        end
        for _,filter in ipairs(filters) do
            if filter.quantity == -1 then filter.quantity = get_num_items(b) end
            if filter.flags2 and filter.flags2.building_material then
                -- blocks get produced at a ratio of 4:1
                filter.quantity = filter.quantity or 1
                filter.quantity = filter.quantity / 4
            end
            process_filter(order_specs, filter, reactions)
        end
    end
    for k,order_spec in pairs(order_specs) do
        local quantity = math.ceil(order_spec.quantity)
        log('ordering %d %s', quantity, k)
        stockflow.create_orders(order_spec.order, quantity)
        table.insert(stats, {label=k, value=quantity})
    end
end
