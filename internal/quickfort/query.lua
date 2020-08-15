-- query-related logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local gui = require('gui')
local guidm = require('gui.dwarfmode')
local quickfort_common = reqscript('internal/quickfort/common')
local log = quickfort_common.log
local quickfort_aliases = reqscript('internal/quickfort/aliases')
local quickfort_keycodes = reqscript('internal/quickfort/keycodes')

local common_aliases_filename = 'hack/data/quickfort/aliases-common.txt'
local user_aliases_filename = 'dfhack-config/quickfort/aliases.txt'

local function load_aliases()
    -- ensure we're starting from a clean alias stack, even if the previous
    -- invocation of this function returned early with an error
    quickfort_aliases.reset_aliases()
    quickfort_aliases.push_aliases_csv_file(common_aliases_filename)
    quickfort_aliases.push_aliases_csv_file(user_aliases_filename)
end

local function is_queryable_tile(pos)
    local flags, occupancy = dfhack.maps.getTileFlags(pos)
    return not flags.hidden and occupancy.building ~= 0
end

local function move_cursor(pos)
    guidm.setCursorPos(pos)
    dfhack.gui.refreshSidebar()
end

local function handle_modifiers(token, modifiers)
    local token_lower = token:lower()
    if token_lower == '{shift}' or
            token_lower == '{ctrl}' or
            token_lower == '{alt}' then
        modifiers[token_lower] = true
        return true
    end
    if token_lower == '{wait}' then
        print('{Wait} not yet implemented')
        return true
    end
    return false
end

function do_run(zlevel, grid, ctx)
    local stats = ctx.stats
    stats.query_keystrokes = stats.zone_designated or
            {label='Keystrokes sent', value=0, always=true}
    stats.query_tiles = stats.zone_tiles or
            {label='Tiles modified', value=0}

    load_aliases()

    local saved_mode = df.global.ui.main.mode
    df.global.ui.main.mode = df.ui_sidebar_mode.QueryBuilding

    for y, row in pairs(grid) do
        for x, cell_and_text in pairs(row) do
            local pos = xyz2pos(x, y, zlevel)
            local cell, text = cell_and_text.cell, cell_and_text.text
            if not is_queryable_tile(pos) then
                print(string.format(
                        'no building at coordinates (%d, %d, %d); skipping ' ..
                        'text in spreadsheet cell %s: "%s"',
                        pos.x, pos.y, pos.z, cell, text))
                goto continue
            end
            log('applying spreadsheet cell %s with text "%s" to map ' ..
                'coordinates (%d, %d, %d)', cell, text, pos.x, pos.y, pos.z)
            local tokens = quickfort_aliases.expand_aliases(text)
            move_cursor(pos)
            local focus_string =
                    dfhack.gui.getFocusString(dfhack.gui.getCurViewscreen(true))
            local modifiers = {} -- tracks ctrl, shift, and alt modifiers
            for _,token in ipairs(tokens) do
                if handle_modifiers(token, modifiers) then goto continue end
                local kcodes = quickfort_keycodes.get_keycodes(token, modifiers)
                if not kcodes then
                    qerror(string.format('unknown key: "%s"', token))
                end
                gui.simulateInput(dfhack.gui.getCurViewscreen(true), kcodes)
                modifiers = {}
                stats.query_keystrokes.value = stats.query_keystrokes.value + 1
                ::continue::
            end
            local new_focus_string =
                    dfhack.gui.getFocusString(dfhack.gui.getCurViewscreen(true))
            if focus_string ~= new_focus_string then
                qerror(string.format(
                    'expected to be back on screen "%s" but screen is "%s"; ' ..
                    'there is likely a problem with the blueprint text in ' ..
                    'cell %s: "%s" (do you need a "^" at the end?)',
                    focus_string, new_focus_string, cell, text))
            end
            stats.query_tiles.value = stats.query_tiles.value + 1
            ::continue::
        end
    end

    df.global.ui.main.mode = saved_mode
    move_cursor(ctx.cursor)
end

function do_orders()
    log('nothing to do for blueprints in mode: query')
end

function do_undo()
    log('cannot undo blueprints for mode: query')
end
