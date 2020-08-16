-- command routing logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local utils = require('utils')
local guidm = require('gui.dwarfmode')
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_list = reqscript('internal/quickfort/list')
local quickfort_orders = reqscript('internal/quickfort/orders')
local quickfort_parse = reqscript('internal/quickfort/parse')

local mode_modules = {}
for mode, _ in pairs(quickfort_common.valid_modes) do
    mode_modules[mode] = reqscript('internal/quickfort/'..mode)
end

function parse_section_name(section_name)
    local sheet_name, label = nil, nil
    if section_name then
        _, _, sheet_name, label = section_name:find('^([^/]*)/?(.*)$')
        if #sheet_name == 0 then sheet_name = nil end
        if #label == 0 then label = nil end
    end
    return sheet_name, label
end

local command_switch = {
    run='do_run',
    orders='do_orders',
    undo='do_undo',
}

function do_command_internal(ctx, section_name)
    local sheet_name, label = parse_section_name(section_name)
    ctx.sheet_name = sheet_name
    local filepath = quickfort_common.get_blueprint_filepath(ctx.blueprint_name)
    local section_data_list = quickfort_parse.process_section(
            filepath, sheet_name, label, ctx.cursor)
    local command = ctx.command
    local first_modeline = nil
    for _, section_data in ipairs(section_data_list) do
        if not first_modeline then first_modeline = section_data.modeline end
        ctx.cursor.z = section_data.zlevel
        mode_modules[section_data.modeline.mode][command_switch[ctx.command]](
            section_data.zlevel, section_data.grid, ctx)
    end
    if first_modeline and first_modeline.message then
        table.insert(ctx.messages, first_modeline.message)
    end
end

local valid_command_args = utils.invert({
    'q',
    '-quiet',
    'v',
    '-verbose',
    'n',
    '-name',
})

function do_command(in_args)
    local command = in_args.action
    if not command or not command_switch[command] then
        qerror(string.format('invalid command: "%s"', command))
    end

    local blueprint_name = table.remove(in_args, 1)
    if not blueprint_name or blueprint_name == '' then
        qerror("expected <list_num> or <blueprint_name> parameter")
    end
    local args = utils.processArgs(in_args, valid_command_args)
    local quiet = args['q'] ~= nil or args['-quiet'] ~= nil
    local verbose = args['v'] ~= nil or args['-verbose'] ~= nil
    local section_name = args['n'] or args['-name']

    local list_num = tonumber(blueprint_name)
    if list_num then
        blueprint_name, section_name =
                quickfort_list.get_blueprint_by_number(list_num)
    end

    local cursor = guidm.getCursorPos()
    if not cursor then
        if command == 'orders' then
            cursor = {x=0, y=0, z=0}
        else
            qerror('please position the game cursor at the blueprint start ' ..
                   'location')
        end
    end

    quickfort_common.verbose = verbose
    local stats = {
        out_of_bounds={label='Tiles outside map boundary', value=0},
        invalid_keys={label='Invalid key sequences', value=0},
    }
    local ctx = {command=command, blueprint_name=blueprint_name, cursor=cursor,
                 stats=stats, messages={}}
    do_command_internal(ctx, section_name)
    if command == 'orders' then quickfort_orders.create_orders(ctx) end
    local section_name_str = ''
    if section_name then
        section_name_str = string.format(' -n "%s"', section_name)
    end
    print(string.format('%s "%s"%s successfully completed',
                        command, blueprint_name, section_name_str))
    if not quiet then
        for _,stat in pairs(stats) do
            if stat.always or stat.value > 0 then
                print(string.format('  %s: %d', stat.label, stat.value))
            end
        end
    end
    if command == 'run' then
        for _,message in ipairs(ctx.messages) do
            print('* '..message)
        end
    end
end
