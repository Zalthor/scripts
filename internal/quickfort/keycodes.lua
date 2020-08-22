-- keycode conversion logic for the quickfort script query module
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local quickfort_common = reqscript('internal/quickfort/common')
local log = quickfort_common.log

local keycodes_file = 'data/init/interface.txt'

local interface_txt_mtime = nil
local keycodes = {}

local function init_keycodes()
    local mtime = dfhack.filesystem.mtime(keycodes_file)
    if interface_txt_mtime == mtime then return end
    local file = io.open(keycodes_file)
    if not file then
        qerror(string.format('failed to open file: "%s"', keycodes_file))
    end
    local cur_binding = nil
    for line in file:lines() do
        line = string.gsub(line, '[\r\n]*$', '')
        _, _, binding = string.find(line, '^%[BIND:([0-9_A-Z]+):.*$')
        if binding then
            cur_binding = binding
        elseif cur_binding and #line > 0 then
            -- it's a keycode definition
            if not keycodes[line] then keycodes[line] = {} end
            table.insert(keycodes[line], cur_binding)
        end
    end
    log('successfully read in keycodes from "%s"', keycodes_file)
    interface_txt_mtime = mtime
end

-- code is an interface key name from the keycodes_file, like 'a' or 'Down',
-- with shift, ctrl, or alt modifiers recorded in the modifiers table.
-- returns a list of all the keycodes that the input could translate to
function get_keycodes(code, modifiers)
    init_keycodes()
    if not code then return nil end
    local mod = 0
    if modifiers['{shift}'] then
        mod = 1
    end
    if modifiers['{ctrl}'] then
        mod = mod + 2
    end
    if modifiers['{alt}'] then
        mod = mod + 4
    end
    local key = nil
    if mod == 0 and #code == 1 then
        key = string.format('[KEY:%s]', code)
    else
        key = string.format('[SYM:%d:%s]', mod, code)
    end
    return keycodes[key]
end
