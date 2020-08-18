-- gui logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local dialogs = require('gui.dialogs')
local guidm = require('gui.dwarfmode')
local quickfort_command = reqscript('internal/quickfort/command')
local quickfort_list = reqscript('internal/quickfort/list')

-- must be at least enough to display all help text on the main dialog
local min_dialog_width = 73

-- persist these between dialog invocations
local show_library = false
local show_hidden = false
local filter_text = nil
local selected_id = nil

local BlueprintDetails = defclass(BlueprintDetails, dialogs.MessageBox)

function BlueprintDetails:onRenderFrame(dc, rect)
    BlueprintDetails.super.onRenderFrame(self, dc, rect)
    dc:seek(rect.x1+2, rect.y2):string('Left arrow', dc.cur_key_pen):
            string(': Back', COLOR_DARKGREY)
end

function BlueprintDetails:onInput(keys)
    if keys.STANDARDSCROLL_LEFT or keys.SELECT or keys.LEAVESCREEN then
        self:dismiss()
    else
        self:inputToSubviews(keys)
    end
end

local BlueprintDialog = defclass(BlueprintDialog, dialogs.ListBox)

BlueprintDialog.ATTRS{
    on_orders = DEFAULT_NIL,
}

function BlueprintDialog:onRenderFrame(dc, rect)
    BlueprintDialog.super.onRenderFrame(self, dc, rect)

    -- render settings help in top row
    local filters_caption = "Filters:"
    local library_caption = "Library: Off"
    local hidden_caption = "Hidden: Off"
    if show_library then library_caption = "Library: On " end
    if show_hidden then hidden_caption = "Hidden: On " end
    local filters_offset = rect.x1 + 2
    local library_offset = filters_offset + #filters_caption + 2
    local hidden_offset = library_offset + #library_caption + 9
    dc:seek(filters_offset, rect.y1+1):string(filters_caption, COLOR_DARKGREY)
    dc:seek(library_offset, rect.y1+1):key('CUSTOM_ALT_L'):
            string(': '..library_caption, COLOR_DARKGREY)
    dc:seek(hidden_offset, rect.y1+1):key('CUSTOM_ALT_H'):
            string(': '..hidden_caption, COLOR_DARKGREY)

    -- render command help on bottom frame
    local orders_caption = "Queue orders"
    local details_key = "Right arrow"
    local details_caption = ": Show details"
    local orders_offset = rect.x1 + 21
    local details_offset = orders_offset + #orders_caption + 9
    dc:seek(orders_offset, rect.y2):key('CUSTOM_ALT_O'):
            string(': '..orders_caption, COLOR_DARKGREY)
    dc:seek(details_offset, rect.y2):string(details_key, dc.cur_key_pen):
            string(details_caption, COLOR_DARKGREY)
end

local function truncate(text, width, max_lines)
    local truncated_text = {}
    for line in text:gmatch('[^\n]*') do
        if #line > width then
            line = line:sub(1, width-5) .. '...->'
        end
        table.insert(truncated_text, line)
        if #truncated_text >= max_lines then break end
    end
    return table.concat(truncated_text, '\n')
end

local function wrap(text, width)
    local wrapped_text = {}
    for line in text:gmatch('[^\n]*') do
        local here = 1
        local wrapped_line = line:gsub(
            '(%s+)()(%S+)()',
            function(sp, st, word, fi)
                if fi - here > width then
                    here = st
                    return '\n' .. word
                end
            end)
        table.insert(wrapped_text, wrapped_line)
    end
    return table.concat(wrapped_text, '\n')
end

local function get_id(text)
    local _, _, id = text:find('^(%d+)')
    return tonumber(id)
end

function BlueprintDialog:refresh()
    local choices = {}
    for _,v in ipairs(
            quickfort_list.do_list_internal(show_library, show_hidden)) do
        local start_comment = ''
        if v.start_comment then
            start_comment = string.format(' cursor start: %s', v.start_comment)
        end
        local text = string.format('%d) %s (%s)%s\n    %s',
                v.id, v.path, v.mode, start_comment, v.comment or '')
        local truncated_text =
                truncate(text, self.frame_body.width, self.row_height)
        table.insert(choices,
                     {text=truncated_text,
                      full_text=text,
                      search_key=v.search_key})
    end
    self.subviews.list:setChoices(choices)
    self:updateLayout()
    if selected_id then
        for idx,v in ipairs(choices) do
            local cur_id = get_id(v.text)
            if selected_id >= cur_id then selected_idx = idx end
            if selected_id <= cur_id then break end
        end
    end
    self.subviews.list:setFilter(filter_text, selected_idx)
end

function BlueprintDialog:onInput(keys)
    if keys.STANDARDSCROLL_RIGHT then
        _,obj = self.subviews.list:getSelected()
        BlueprintDetails{
            frame_title='Details',
            text=wrap(obj.full_text, self.frame_body.width)
        }:show()
    elseif keys.CUSTOM_ALT_O then
        self.on_orders(self.subviews.list:getSelected())
    elseif keys.CUSTOM_ALT_L then
        show_library = not show_library
        self:refresh()
    elseif keys.CUSTOM_ALT_H then
        show_hidden = not show_hidden
        self:refresh()
    elseif keys.LEAVESCREEN then
        self:dismiss()
        if self.on_cancel then
            self.on_cancel()
        end
    else
        self:inputToSubviews(keys)
    end
    filter_text = self.subviews.list:getFilter()
    local _, selected_obj = self.subviews.list:getSelected()
    if selected_obj then
        selected_id = get_id(selected_obj.text)
    else
        selected_id = nil
    end
end

local function dialog_command(command, text)
    local cursor = guidm.getCursorPos()
    if not cursor then
        if command == 'orders' then
            cursor = {x=0, y=0, z=0}
        else
            dialogs.showMessage('Error',
                'Please position the game cursor at the blueprint start ' ..
                'location')
            return
        end
    end

    local id = get_id(text)
    local blueprint_name, section_name =
            quickfort_list.get_blueprint_by_number(id)

    local ctx = {command=command, blueprint_name=blueprint_name, cursor=cursor,
                 stats={}, messages={}}
    quickfort_command.do_command_internal(ctx, section_name)
    quickfort_command.finish_command(ctx, section_name, true)
    if command == 'run' and #ctx.messages > 0 then
        dialogs.showMessage('Attention',
                            wrap(table.concat(ctx.messages, '\n\n'),
                                 min_dialog_width))
    end
end

function do_dialog()
    local blueprint_dialog = BlueprintDialog{
        frame_title='Select quickfort blueprint',
        with_filter=true,
        frame_width=min_dialog_width,
        row_height=2,
        select2_hint='Undo',
        on_select=function(idx, obj) dialog_command('run', obj.text) end,
        on_select2=function(idx, obj) dialog_command('undo', obj.text) end,
        on_orders=function(idx, obj) dialog_command('orders', obj.text) end,
    }
    blueprint_dialog:show()
    blueprint_dialog:refresh() -- sets the choices and updates the layout
end
