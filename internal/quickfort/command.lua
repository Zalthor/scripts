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

local command_switch = {
    run='do_run',
    orders='do_orders',
    undo='do_undo',
}

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
    local list_num = tonumber(blueprint_name)
    local sheet_name = nil
    if list_num then
        blueprint_name, sheet_name =
                quickfort_list.get_blueprint_by_number(list_num)
    end
    local args = utils.processArgs(in_args, valid_command_args)
    local quiet = args['q'] ~= nil or args['-quiet'] ~= nil
    local verbose = args['v'] ~= nil or args['-verbose'] ~= nil
    sheet_name = sheet_name or args['n'] or args['-name']

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

    local filepath = quickfort_common.get_blueprint_filepath(blueprint_name)
    local data = quickfort_parse.process_file(filepath, sheet_name, cursor)
    for zlevel, section_data_list in pairs(data) do
        for _, section_data in ipairs(section_data_list) do
            local modeline = section_data.modeline
            local stats = mode_modules[modeline.mode][command_switch[command]](
                zlevel,
                section_data.grid)
            if stats and not quiet then
                if command == 'orders' then
                    print('ordered:')
                else
                    print(string.format('%s on z-level %d',
                                        modeline.mode, zlevel))
                end
                for _, stat in pairs(stats) do
                    if stat.always or stat.value > 0 then
                        print(string.format('  %s: %d', stat.label, stat.value))
                    end
                end
            end
        end
    end
    local sheet_name_param = ''
    if sheet_name then
        sheet_name_param = string.format(' -n "%s"', sheet_name)
    end
    print(string.format('%s "%s"%s successfully completed',
                        command, blueprint_name, sheet_name_param))
end
