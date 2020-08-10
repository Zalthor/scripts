-- DFHack-native implementation of the classic Quickfort utility (PRE-RELEASE)
--[====[

quickfort
=========
Processes Quickfort-style blueprint files. This is a pre-release -- not all
features are implemented yet.

Quickfort blueprints record what you want at each map coordinate in a
spreadsheet, storing the keys in a spreadsheet cell that you would press to make
something happen at that spot on the DF map. Quickfort runs in one of four
modes: ``dig``, ``build``, ``place``, or ``query``. ``dig`` designates tiles for
digging, ``build`` builds buildings and constructions, ``place`` places
stockpiles, and ``query`` changes building or stockpile settings. The mode is
determined by a marker in the upper-left cell of the spreadsheet (e.g.: ``#dig``
in cell ``A1``).

You can create these blueprints by hand or by using any spreadsheet application,
saving them as ``.xlsx`` or ``.csv`` files. You can also build your plan "for
real" in Dwarf Fortress, and then export your map using the DFHack
`blueprint plugin`_ for later replay. Blueprint files should go in the
``blueprints`` subfolder in the main DF folder.

For more details on blueprint file syntax, see the `Blueprints Guidebook`_ or
browse through the ready-to-use examples in the `blueprints/library`_ folder.

Usage:

**quickfort set [<key> <value>]**
    Allows you to modify the active quickfort configuration. Just run
    ``quickfort set`` to show current settings. See the Configuration section
    below for available keys and values.
**quickfort reset**
    Resets quickfort configuration to the defaults in ``quickfort.txt``.
**quickfort list [search string] [-m|--mode <mode>] [-l|--library]**
    Lists blueprints in the ``blueprints`` folder. Blueprints are ``.csv`` files
    or sheets within ``.xlsx`` files that contain a ``#<mode>`` comment in the
    upper-left cell. By default, blueprints in the ``blueprints/library/``
    subfolder are not shown. Specify ``-l`` to include library blueprints. The
    list can be filtered by a specified mode (e.g. "-m build") and/or a
    substring to search for in a path, filename, mode, or comment.
**quickfort <command> <list_num> [<options>]**
    Applies the blueprint with the number from the list command.
**quickfort <command> <filename> [-n|--name <sheet_name>] [<options>]**
    Applies the blueprint from the named file. If it is an ``.xlsx`` file,
    the ``-n`` (or ``--name``) parameter can identify the sheet name. If the
    sheet name is not specified, the first sheet is used.

**<command>** can be one of:

:run:     Applies the blueprint at your current cursor position. It doesn't
          matter which mode you are in. You just need an active cursor.
:orders:  Uses the manager interface to queue up orders for the specified
          build-mode blueprint.
:undo:    Applies the inverse of the specified blueprint. Dig tiles are
          undesignated, buildings are canceled or removed (depending on their
          construction status), and stockpiles are removed. There is no effect
          for query blueprints.

**<options>** can be zero or more of:

``-q``, ``--quiet``
    Don't report on what actions were taken (error messages are still shown).
``-v``, ``--verbose``
    Output extra debugging information. This is especially useful if the
    blueprint isn't being applied like you expect.

Configuration:

The quickfort script reads its startup configuration from the
``dfhack-config/quickfort/quickfort.txt`` file, which you can customize. The
following settings may be dynamically modified by the ``quickfort set`` command,
but settings changed with the ``quickfort set`` command will not change the
configuration stored in the file:

``blueprints_dir`` (default: 'blueprints')
    Directory tree to search for blueprints. Can be set to an absolute or
    relative path. If set to a relative path, resolves to a directory under the
    DF folder.
``force_marker_mode`` (default: 'false')
    Set to "true" or "false". If true, will designate dig blueprints in marker
    mode. If false, only cells with dig codes explicitly prefixed with ``m``
    will be designated in marker mode.
``stockpiles_max_barrels``, ``stockpiles_max_bins``, and ``stockpiles_max_wheelbarrows`` (defaults: -1, -1, 0)
    Set to the maximum number of resources you want assigned to stockpiles of
    the relevant types. Set to -1 for DF defaults (number of stockpile tiles
    for stockpiles that take barrels and bins, 1 wheelbarrow for stone
    stockpiles). The default here for wheelbarrows is 0 since using wheelbarrows
    normally *decreases* the efficiency of your fort.

There are also two other configuration files in the ``dfhack-config/quickfort``
folder: `aliases.txt`_ and `materials.txt`_. ``aliases.txt`` defines keycode
shortcuts for query blueprints, and ``materials.txt`` defines forbidden
materials and material preferences for build blueprints. The formats for these
files are described in the files themselves, and default configuration that all
players can build on is stored in `aliases-common.txt`_ and
`materials-common.txt`_ in the ``hack/data/quickfort/`` directory.

.. _blueprint plugin: https://docs.dfhack.org/en/stable/docs/Plugins.html#blueprint
.. _Blueprints Guidebook: https://github.com/DFHack/dfhack/tree/develop/data/blueprints
.. _blueprints/library: https://github.com/DFHack/dfhack/tree/develop/data/blueprints/library
.. _aliases.txt: https://github.com/DFHack/dfhack/tree/develop/dfhack-config/quickfort/aliases.txt
.. _materials.txt: https://github.com/DFHack/dfhack/tree/develop/dfhack-config/quickfort/materials.txt
.. _aliases-common.txt: https://github.com/DFHack/dfhack/tree/develop/data/quickfort/aliases-common.txt
.. _materials-common.txt: https://github.com/DFHack/dfhack/tree/develop/data/quickfort/materials-common.txt
]====]

-- reqscript all internal files here, even if they're not directly used by this
-- top-level file. this ensures transitive dependencies are reloaded if any
-- files have changed.
local quickfort_aliases = reqscript('internal/quickfort/aliases')
local quickfort_build = reqscript('internal/quickfort/build')
local quickfort_building = reqscript('internal/quickfort/building')
local quickfort_command = reqscript('internal/quickfort/command')
local quickfort_common = reqscript('internal/quickfort/common')
local quickfort_dig = reqscript('internal/quickfort/dig')
local quickfort_keycodes = reqscript('internal/quickfort/keycodes')
local quickfort_list = reqscript('internal/quickfort/list')
local quickfort_parse = reqscript('internal/quickfort/parse')
local quickfort_place = reqscript('internal/quickfort/place')
local quickfort_query = reqscript('internal/quickfort/query')
local quickfort_set = reqscript('internal/quickfort/set')

-- keep this in sync with the full help text above
local function print_short_help()
    print [[
Usage:

quickfort set [<key> <value>]
    Allows you to modify the active quickfort configuration. Just run
    "quickfort set" to show current settings.
quickfort reset
    Resets quickfort configuration to defaults.
quickfort list [-l|--library]
    Lists blueprints in the "blueprints" folder. Specify -l to include library
    blueprints.
quickfort <command> <list_num> [<options>]
    Applies the blueprint with the number from the list command.
quickfort <command> <filename> [-s|--sheet <sheet_num>] [<options>]
    Applies the blueprint from the named file. If it is an .xlsx file, the -s
    parameter is required to identify the sheet. The first sheet is "-s 1".

<command> can be one of:

run     Applies the blueprint at your current cursor position. It doesn't matter
        which mode you are in. You just need an active cursor.
orders  Uses the manager interface to queue up orders for the specified
        build-mode blueprint.
undo    Applies the inverse of the specified blueprint. Dig tiles are
        undesignated, buildings are canceled or removed (depending on their
        construction status), and stockpiles are removed. There is no effect for
        query blueprints.

<options> can be zero or more of:

-q, --quiet
    Don't report on what actions were taken (error messages are still shown).
-v, --verbose
    Output extra debugging information. This is especially useful if the
    blueprint isn't being applied like you expect.

For more info, see:
https://docs.dfhack.org/en/stable/docs/_auto/base.html#quickfort
]]
end

local action_switch = {
    set=quickfort_set.do_set,
    reset=quickfort_set.do_reset,
    list=quickfort_list.do_list,
    run=quickfort_command.do_command,
    orders=quickfort_command.do_command,
    undo=quickfort_command.do_command
}
setmetatable(action_switch, {__index=function() return print_short_help end})

local args = {...}
local action = table.remove(args, 1) or 'help'
args['action'] = action

action_switch[action](args)
