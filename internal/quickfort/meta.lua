-- meta-blueprint logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local quickfort_common = reqscript('internal/quickfort/common')
local log = quickfort_common.log
local quickfort_command = reqscript('internal/quickfort/command')

-- blueprints referenced by meta blueprints must have a label
local function get_section_name(text, cur_sheet_name)
    local sheet_name, label = quickfort_command.parse_section_name(text)
    if not label then return nil end
    if not sheet_name then sheet_name = cur_sheet_name or '' end
    return string.format('%s/%s', sheet_name, label)
end

local function sort_cells(cell_a, cell_b)
    return cell_a.y < cell_b.y or
            (cell_a.y == cell_b.y and cell_a.x < cell_b.x)
end

local function do_meta(zlevel, grid, ctx)
    local stats = ctx.stats or {
        blueprints={label='Blueprints applied', value=0, always=true},
    }
    ctx.stats = stats
    local cells = {}
    for y, row in pairs(grid) do
        for x, cell_and_text in pairs(row) do
            local cell, text = cell_and_text.cell, cell_and_text.text
            local section_name = get_section_name(text, ctx.sheet_name)
            if not section_name then
                qerror(string.format(
                        'malformed blueprint section name in cell %s ' ..
                        '(labels are required; did you mean "/%s"?): "%s"',
                        cell, text, text))
            end
            table.insert(cells, {y=y, x=x, section_name=section_name})
        end
    end
    table.sort(cells, sort_cells)
    for _, cell in ipairs(cells) do
        quickfort_command.do_command_internal(ctx, cell.section_name)
        stats.blueprints.value = stats.blueprints.value + 1
    end
    return stats
end

function do_run(zlevel, grid, ctx)
    return do_meta(zlevel, grid, ctx)
end

function do_orders(zlevel, grid, ctx)
    return do_meta(zlevel, grid, ctx)
end

function do_undo(zlevel, grid, ctx)
    return do_meta(zlevel, grid, ctx)
end
