-- command routing logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local utils = require('utils')
local guidm = require('gui.dwarfmode')
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_parse = reqscript('internal/quickfort/parse')
local quickfort_list = reqscript('internal/quickfort/list')

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
    local top_level = ctx.top_level
    ctx.top_level = false
    local sheet_name, label = parse_section_name(section_name)
    ctx.sheet_name = sheet_name
    local filepath = quickfort_common.get_blueprint_filepath(ctx.blueprint_name)
    local section_data_list = quickfort_parse.process_section(
            filepath, sheet_name, label, ctx.cursor)
    local command = ctx.command
    for _, section_data in ipairs(section_data_list) do
        local modeline = section_data.modeline
        ctx.cursor.z = section_data.zlevel
        local stats = mode_modules[modeline.mode][command_switch[command]](
                section_data.zlevel, section_data.grid, ctx)
        if stats and not ctx.quiet and modeline.mode ~= 'meta' then
            if command == 'orders' then
                print('ordered:')
            else
                print(string.format('%s on z-level %d',
                                    modeline.mode, section_data.zlevel))
            end
            for _, stat in pairs(stats) do
                if stat.always or stat.value > 0 then
                    print(string.format('  %s: %d', stat.label, stat.value))
                end
            end
        end
    end
    local section_name_str = ''
    if section_name then
        section_name_str = string.format(' -n "%s"', section_name)
    end
    local top_level_is_meta = ctx.stats and top_level
    if top_level_is_meta then
        print(string.format('meta %s "%s"%s successfully completed',
                            command, ctx.blueprint_name, section_name_str))
        if not ctx.quiet and top_level_is_meta then
            for _, stat in pairs(ctx.stats) do
                if stat.always or stat.value > 0 then
                    print(string.format('  %s: %d', stat.label, stat.value))
                end
            end
        end
    else
        print(string.format('%s "%s"%s successfully completed',
                            command, ctx.blueprint_name, section_name_str))
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
    local ctx = {command=command, blueprint_name=blueprint_name,
                 cursor=cursor, quiet=quiet, top_level=true}
    do_command_internal(ctx, section_name)
end
