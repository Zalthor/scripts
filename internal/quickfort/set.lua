-- settings management logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local quickfort_common = reqscript('internal/quickfort/common')

local valid_booleans = {
    ['true']=true,
    ['1']=true,
    ['on']=true,
    ['false']=false,
    ['0']=false,
    ['off']=false,
}

local function set_setting(key, value)
    if quickfort_common.settings[key] == nil then
        qerror(string.format('error: invalid setting: "%s"', key))
    end
    if type(quickfort_common.settings[key].value) == 'boolean' then
        if valid_booleans[value] == nil then
            qerror(string.format('error: invalid boolean: "%s"', value))
        end
        value = valid_booleans[value]
    elseif type(quickfort_common.settings[key].value) == 'number' then
        if tonumber(value) == nil then
            qerror(string.format('error: invalid integer: "%s"', value))
        end
        value = math.floor(tonumber(value))
    end
    quickfort_common.settings[key].value = value
end

local function read_config(filename)
    print(string.format('reading configuration from "%s"', filename))
    for line in io.lines(filename) do
        local _, _, key, value = string.find(line, '^%s*([%a_]+)%s*=%s*(%S.*)')
        if (key) then
            set_setting(key, value)
        end
    end
end

local function print_settings()
    print('active settings:')
    local width = 1
    local settings_arr = {}
    for k,v in pairs(quickfort_common.settings) do
        if not v.deprecated then
            if #k > width then width = #k end
            table.insert(settings_arr, k)
        end
    end
    table.sort(settings_arr)
    for _, k in ipairs(settings_arr) do
        print(string.format('  %-'..width..'s = %s',
                            k, quickfort_common.settings[k].value))
    end
end

function do_set(args)
    if #args == 0 then print_settings() return end
    if #args ~= 2 then
        qerror('error: expected "quickfort set [<key> <value>]"')
    end
    set_setting(args[1], args[2])
    print(string.format('successfully set %s to "%s"',
                        args[1], quickfort_common.settings[args[1]].value))
end

function do_reset()
    read_config('dfhack-config/quickfort/quickfort.txt')
end

if not initialized then
    -- this is the first time we're initializing the environment
    do_reset()
    initialized = true
end
