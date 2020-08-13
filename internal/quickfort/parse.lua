-- file parsing logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local xlsxreader = require('plugins.xlsxreader')
local quickfort_common = reqscript('internal/quickfort/common')

local function trim_and_insert(tokens, token)
    _, _, token = token:find('^%s*(.-)%s*$')
    table.insert(tokens, token)
end

local function get_next_line(file)
    local line = file:read()
    if not line then return nil end
    return string.gsub(line, '[\r\n]*$', '')
end

-- adapted from example on http://lua-users.org/wiki/LuaCsv
-- returns a list of strings corresponding to the text in the cells in the row
local function tokenize_next_csv_line(file)
    local line = get_next_line(file)
    if not line then return nil end
    local tokens = {}
    local pos = 1
    local sep = ','
    while true do
        local c = string.sub(line, pos, pos)
        if c == '' then break end
        if c == '"' then
            -- quoted value (ignore separator within)
            local txt = ''
            repeat
                local startp, endp = string.find(line, '^%b""', pos)
                while not startp do
                    -- handle multi-line quoted string
                    local next_line = get_next_line(file)
                    if not next_line then
                        dfhack.printerr(
                            'unterminated quoted string in .csv file')
                        return nil
                    end
                    line = line .. '\n' .. next_line
                    startp, endp = string.find(line, '^%b""', pos)
                end
                txt = txt .. string.sub(line, startp+1, endp-1)
                pos = endp + 1
                c = string.sub(line, pos, pos)
                if (c == '"') then txt = txt .. '"' end
                -- check first char AFTER quoted string, if it is another
                -- quoted string without separator, then append it
                -- this is the way to "escape" the quote char in a quote.
                -- example: "blub""blip""boing" -> blub"blip"boing
            until c ~= '"'
            trim_and_insert(tokens, txt)
            assert(c == sep or c == '')
            pos = pos + 1
        else
            -- no quotes used, just look for the first separator
            local startp, endp = string.find(line, sep, pos)
            if startp then
                trim_and_insert(tokens, string.sub(line, pos, startp-1))
                pos = endp + 1
            else
                -- no separator found -> use rest of string and terminate
                trim_and_insert(tokens, string.sub(line, pos))
                break
            end
        end
    end
    return tokens
end

local function parse_label(modeline, start_pos, filename, marker_values)
    local _, label_str_end, label_str =
            string.find(modeline, '^%s+label(%b())', start_pos)
    if not label_str then
        return false, start_pos
    end
    local _, _, label = string.find(label_str, '^%(%s*(%a.-)%s*%)$')
    if not label or #label == 0 then
        print(string.format(
            'error while parsing "%s": labels must start with a letter: "%s"',
            filename, modeline))
    else
        marker_values.label = label
    end
    return true, label_str_end + 1
end

local function parse_start(modeline, start_pos, filename, marker_values)
    local _, start_str_end, start_str =
            string.find(modeline, '^%s+start(%b())', start_pos)
    if not start_str or #start_str == 0 then
        return false, start_pos
    end
    _, _, startx, starty, start_comment =
            string.find(start_str, '^%(%s*(%d+)%s*[;, ]%s*(%d+)%s*[;, ]?%s*(.*)%)$')
    if not startx or not starty then
        print(string.format(
            'error while parsing "%s": invalid start offsets: %s',
            filename, modeline))
        marker_values.startx = 1
        marker_values.starty = 1
    else
        marker_values.startx = startx
        marker_values.starty = starty
        marker_values.start_comment = start_comment
    end
    return true, start_str_end + 1
end

local function parse_hidden(modeline, start_pos, filename, marker_values)
    local _, hidden_str_end, hidden_str =
            string.find(modeline, '^%s+hidden(%b())', start_pos)
    if not hidden_str or #hidden_str == 0 then return false, start_pos end
    marker_values.hidden = true
    return true, hidden_str_end + 1
end

local marker_fns = {parse_label, parse_start, parse_hidden}

-- parses all markers in any order
-- returns table of found values: {label, startx, starty, start_comment, hidden}
local function parse_markers(modeline, start_pos, filename)
    local remaining_marker_fns = copyall(marker_fns)
    local marker_values = {}
    while #remaining_marker_fns > 0 do
        local matched = false
        for i,marker_fn in ipairs(remaining_marker_fns) do
            matched, start_pos =
                    marker_fn(modeline, start_pos, filename, marker_values)
            if matched then
                table.remove(remaining_marker_fns, i)
                break
            end
        end
        if not matched then break end
    end
    return marker_values, start_pos
end

--[[
parses a modeline
example: '#dig label(dig1) start(4;4;center of stairs) dining hall'
where all elements other than the initial #mode are optional (though if the
'label' part exists, a label must be specified, and if the 'start' part exists,
the offsets must also exist). If a label is not specified, the modeline_id is
used as the label.
returns a table in the format:
  {mode, label, startx, starty, start_comment, comment}
or nil if the modeline is invalid
]]
local function parse_modeline(modeline, filename, modeline_id)
    if not modeline then return nil end
    local _, mode_end, mode = string.find(modeline, '^#([%l]+)')
    if not mode or not quickfort_common.valid_modes[mode] then
        return nil
    end
    local modeline_data, comment_start =
            parse_markers(modeline, mode_end+1, filename)
    local _, _, comment = string.find(modeline, '^%s*(.*)', comment_start)
    modeline_data.mode = mode
    modeline_data.comment = comment
    modeline_data.label = modeline_data.label or modeline_id
    return modeline_data
end

local function get_col_name(col)
  if col <= 26 then
    return string.char(string.byte('A') + col - 1)
  end
  local div, mod = math.floor(col / 26), math.floor(col % 26)
  if mod == 0 then
      mod = 26
      div = div - 1
  end
  return get_col_name(div) .. get_col_name(mod)
end

local function make_cell_label(col_num, row_num)
    return get_col_name(col_num) .. tostring(math.floor(row_num))
end

local function read_csv_line(ctx)
    return tokenize_next_csv_line(ctx.csv_file)
end

local function cleanup_csv_ctx(ctx)
    ctx.csv_file:close()
end

local function read_xlsx_line(ctx)
    return xlsxreader.get_row(ctx.xlsx_sheet)
end

local function cleanup_xslx_ctx(ctx)
    xlsxreader.close_sheet(ctx.xlsx_sheet)
    xlsxreader.close_xlsx_file(ctx.xlsx_file)
end

local function init_reader_ctx(filepath, sheet_name)
    local reader_ctx = {filepath=filepath}
    if string.find(filepath:lower(), '[.]csv$') then
        local file = io.open(filepath)
        if not file then
            qerror(string.format('failed to open blueprint file: "%s"',
                                 filepath))
        end
        reader_ctx.csv_file = file
        reader_ctx.get_row_tokens = read_csv_line
        reader_ctx.cleanup = cleanup_csv_ctx
    else
        local xlsx_file = xlsxreader.open_xlsx_file(filepath)
        if not xlsx_file then
            qerror(string.format('failed to open blueprint file: "%s"',
                                 filepath))
        end
        if not sheet_name then
            for _, sheet in ipairs(xlsxreader.list_sheets(xlsx_file)) do
                sheet_name = sheet
                break
            end
        end
        -- open_sheet succeeds even if the sheet cannot be found
        reader_ctx.xlsx_file = xlsx_file
        reader_ctx.sheet_name = sheet_name
        reader_ctx.xlsx_sheet =
                xlsxreader.open_sheet(reader_ctx.xlsx_file, sheet_name)
        reader_ctx.get_row_tokens = read_xlsx_line
        reader_ctx.cleanup = cleanup_xslx_ctx
    end
    return reader_ctx
end

-- returns a grid representation of the current level, the number of lines
-- read from the input, and the next z-level modifier, if any. See process_file
-- for grid format.
local function process_level(reader_ctx, start_line_num, start_coord)
    local grid = {}
    local y = start_coord.y
    while true do
        local row_tokens = reader_ctx.get_row_tokens(reader_ctx)
        if not row_tokens then return grid, y-start_coord.y end
        for i, v in ipairs(row_tokens) do
            if i == 1 then
                if v == '#<' then return grid, y-start_coord.y, 1 end
                if v == '#>' then return grid, y-start_coord.y, -1 end
                if parse_modeline(v, reader_ctx.filepath) then
                    return grid, y-start_coord.y
                end
            end
            if string.find(v, '^#') then break end
            if not string.find(v, '^[`~%s]*$') then
                -- cell has actual content, not just spaces or comment chars
                if not grid[y] then grid[y] = {} end
                local x = start_coord.x + i - 1
                local line_num = start_line_num + y - start_coord.y
                grid[y][x] = {cell=make_cell_label(i, line_num), text=v}
            end
        end
        y = y + 1
    end
end

local function process_levels(reader_ctx, label, start_cursor_coord)
    local section_data_list = {}
    -- scan down to the target label
    local cur_line_num, modeline_id = 1, 1
    local row_tokens, modeline = nil, nil
    while not modeline or (label and modeline.label ~= label) do
        row_tokens = reader_ctx.get_row_tokens(reader_ctx)
        if not row_tokens then
            local label_str = 'no data'
            if label then label_str = string.format('label "%s" not', label) end
            if reader_ctx.sheet_name then
                qerror(string.format(
                        '%s found in sheet "%s" in file "%s"',
                        label_str, reader_ctx.sheet_name, reader_ctx.filepath))
            else
                qerror(string.format('%s found in file "%s"',
                                     label_str, reader_ctx.filepath))
            end
        end
        cur_line_num = cur_line_num + 1
        modeline = parse_modeline(row_tokens[1], reader_ctx.filepath,
                                  tostring(modeline_id))
        if modeline then modeline_id = modeline_id + 1 end
    end
    local x = start_cursor_coord.x - modeline.startx + 1
    local y = start_cursor_coord.y - modeline.starty + 1
    local z = start_cursor_coord.z
    while true do
        local grid, num_section_rows, zmod =
                process_level(reader_ctx, cur_line_num, xyz2pos(x, y, z))
        for _, _ in pairs(grid) do
            -- apparently, the only way to tell if a sparse array is not empty
            table.insert(section_data_list,
                         {modeline=modeline, zlevel=z, grid=grid})
            break;
        end
        if zmod == nil then break end
        cur_line_num = cur_line_num + num_section_rows + 1
        z = z + zmod
    end
    return section_data_list
end

local function get_sheet_modelines(reader_ctx)
    local modelines = {}
    local row_tokens = reader_ctx.get_row_tokens(reader_ctx)
    while row_tokens do
        if #row_tokens > 0 then
            local modeline = parse_modeline(row_tokens[1], reader_ctx.filepath,
                                            tostring(#modelines+1))
            if modeline then table.insert(modelines, modeline) end
        end
        row_tokens = reader_ctx.get_row_tokens(reader_ctx)
    end
    return modelines
end

-- returns a list of modeline tables
function get_modelines(filepath, sheet_name)
    local reader_ctx = init_reader_ctx(filepath, sheet_name)
    return dfhack.with_finalize(
        function() reader_ctx.cleanup(reader_ctx) end,
        function() return get_sheet_modelines(reader_ctx) end
    )
end

--[[
returns a list of {modeline, zlevel, grid} tables
Where the structure of modeline is defined as per parse_modeline and grid is a:
  map of target y coordinate ->
    map of target map x coordinate ->
      {cell=spreadsheet cell, text=text from spreadsheet cell}
Map keys are numbers, and the keyspace is sparse -- only cells that have content
are non-nil.
]]
function process_section(filepath, sheet_name, label, start_cursor_coord)
    local reader_ctx = init_reader_ctx(filepath, sheet_name)
    return dfhack.with_finalize(
        function() reader_ctx.cleanup(reader_ctx) end,
        function()
            return process_levels(reader_ctx, label, start_cursor_coord)
        end
    )
end
