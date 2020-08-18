-- list-related logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local utils = require('utils')
local xlsxreader = require('plugins.xlsxreader')
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_parse = reqscript('internal/quickfort/parse')

local blueprint_cache = {}

local function scan_csv_blueprint(path)
    local filepath = quickfort_common.get_blueprint_filepath(path)
    local mtime = dfhack.filesystem.mtime(filepath)
    if not blueprint_cache[path] or blueprint_cache[path].mtime ~= mtime then
        blueprint_cache[path] =
                {modelines=quickfort_parse.get_modelines(filepath), mtime=mtime}
    end
    if #blueprint_cache[path].modelines == 0 then
        print(string.format('skipping "%s": no #mode markers detected', path))
    end
    return blueprint_cache[path].modelines
end

local function get_xlsx_file_sheet_infos(filepath)
    local xlsx_file = xlsxreader.open_xlsx_file(filepath)
    return dfhack.with_finalize(
        function() xlsxreader.close_xlsx_file(xlsx_file) end,
        function()
            local sheet_infos = {}
            for _, sheet_name in ipairs(xlsxreader.list_sheets(xlsx_file)) do
                local modelines =
                        quickfort_parse.get_modelines(filepath, sheet_name)
                if #modelines > 0 then
                    table.insert(sheet_infos,
                                 {name=sheet_name, modelines=modelines})
                end
            end
            return sheet_infos
        end
    )
end

local function scan_xlsx_blueprint(path)
    local filepath = quickfort_common.get_blueprint_filepath(path)
    local mtime = dfhack.filesystem.mtime(filepath)
    if blueprint_cache[path] and blueprint_cache[path].mtime == mtime then
        return blueprint_cache[path].sheet_infos
    end
    local sheet_infos = get_xlsx_file_sheet_infos(filepath)
    if #sheet_infos == 0 then
        print(string.format(
                'skipping "%s": no sheet with #mode markers detected', v.path))
    end
    blueprint_cache[path] = {sheet_infos=sheet_infos, mtime=mtime}
    return sheet_infos
end

local blueprints = {}

local function scan_blueprints()
    local paths = dfhack.filesystem.listdir_recursive(
        quickfort_common.settings['blueprints_dir'].value, nil, false)
    blueprints = {}
    local library_blueprints = {}
    for _, v in ipairs(paths) do
        local is_library = string.find(v.path, '^library/') ~= nil
        local target_list = blueprints
        if is_library then target_list = library_blueprints end
        if not v.isdir and string.find(v.path:lower(), '[.]csv$') then
            local modelines = scan_csv_blueprint(v.path)
            for _,modeline in ipairs(modelines) do
                table.insert(target_list,
                        {path=v.path, modeline=modeline, is_library=is_library})
            end
        elseif not v.isdir and string.find(v.path:lower(), '[.]xlsx$') then
            local sheet_infos = scan_xlsx_blueprint(v.path)
            if #sheet_infos > 0 then
                for _,sheet_info in ipairs(sheet_infos) do
                    for _,modeline in ipairs(sheet_info.modelines) do
                        table.insert(target_list,
                                     {path=v.path,
                                      sheet_name=sheet_info.name,
                                      modeline=modeline,
                                      is_library=is_library})
                    end
                end
            end
        end
    end
    -- tack library files on to the end so user files are contiguous
    for i=1, #library_blueprints do
        blueprints[#blueprints + 1] = library_blueprints[i]
    end
end

local function get_section_name(sheet_name, label)
    if not sheet_name and not (label and label ~= "1") then return nil end
    local sheet_name_str, label_str = '', ''
    if sheet_name then sheet_name_str = sheet_name end
    if label and label ~= "1" then label_str = '/' .. label end
    return string.format('%s%s', sheet_name_str, label_str)
end

function get_blueprint_by_number(list_num)
    if #blueprints == 0 then
        scan_blueprints()
    end
    list_num = tonumber(list_num)
    local blueprint = blueprints[list_num]
    if not blueprint then
        qerror(string.format('invalid list index: %d', list_num))
    end
    local section_name =
            get_section_name(blueprint.sheet_name, blueprint.modeline.label)
    return blueprint.path, section_name
end

-- returns a sequence of structured data to display. note that the id may not
-- be equal to the list index due to holes left by hidden blueprints.
function do_list_internal(show_library, show_hidden)
    scan_blueprints()
    local display_list = {}
    for i,v in ipairs(blueprints) do
        if not show_library and v.is_library then goto continue end
        if not show_hidden and v.modeline.hidden then goto continue end
        local display_data = {
            id=i,
            path=v.path,
            mode=v.modeline.mode,
            section_name=get_section_name(v.sheet_name, v.modeline.label),
            start_comment=v.modeline.start_comment,
            comment=v.modeline.comment,
        }
        local search_key = ''
        for _,v in pairs(display_data) do
            if v then
                -- order doesn't matter; we just need all the strings in there
                search_key = string.format('%s %s', search_key, tostring(v))
            end
        end
        display_data.search_key = search_key
        table.insert(display_list, display_data)
        ::continue::
    end
    return display_list
end

local valid_list_args = utils.invert({
    'h',
    '-hidden',
    'l',
    '-library',
    'm',
    '-mode',
})

function do_list(in_args)
    local filter_string = nil
    if #in_args > 0 and not in_args[1]:startswith('-') then
        filter_string = table.remove(in_args, 1)
    end
    local args = utils.processArgs(in_args, valid_list_args)
    local show_library = args['l'] ~= nil or args['-library'] ~= nil
    local show_hidden = args['h'] ~= nil or args['-hidden'] ~= nil
    local filter_mode = args['m'] or args['-mode']
    if filter_mode and not quickfort_common.valid_modes[filter_mode] then
        qerror(string.format('invalid mode: "%s"', filter_mode))
    end
    local list = do_list_internal(show_library, show_hidden)
    local num_filtered = 0
    for _,v in ipairs(list) do
        if (filter_string and not string.find(v.search_key, filter_string)) or
                (filter_mode and v.modeline.mode ~= filter_mode) then
            num_filtered = num_filtered + 1
            goto continue
        end
        local sheet_spec = ''
        if v.section_name then
            sheet_spec = string.format(' -n "%s"', section_name)
        end
        local comment = ')'
        if v.comment then comment = string.format(': %s)', v.comment) end
        local start_comment = ''
        if v.start_comment then
            start_comment = string.format('; cursor start: %s', v.start_comment)
        end
        print(string.format(
                '%d) "%s"%s (%s%s%s',
                v.id, v.path, sheet_spec, v.mode, comment, start_comment))
        ::continue::
    end
    if num_filtered > 0 then
        print(string.format('  %d blueprints did not match filter',
                            num_filtered))
    end
end
