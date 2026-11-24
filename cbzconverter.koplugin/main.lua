local ConfirmBox = require("ui/widget/confirmbox")
local Converter = require("cbz_converter")
local InfoMessage = require("ui/widget/infomessage")
local Job = require("cbz_job")
local PathChooser = require("ui/widget/pathchooser")
local T = require("cbz_i18n")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local CbzConverter = WidgetContainer:extend{
    name = "cbzconverter",
    is_doc_only = false,
}

local function ext_of(path)
    return (path:match("%.([^./]+)$") or ""):lower()
end

local function refresh_file_manager()
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance and FileManager.instance.file_chooser then
        FileManager.instance.file_chooser:refreshPath()
    end
end

function CbzConverter:init()
    self.ui.menu:registerToMainMenu(self)
    -- Lang drücken auf eine Datei im Dateimanager
    if self.ui.addFileDialogButtons then
        self.ui:addFileDialogButtons("cbzconverter", function(file, is_file)
            if is_file and Converter.SUPPORTED[ext_of(file)] then
                return { {
                    text = T("button_convert"),
                    callback = function()
                        local FileManager = require("apps/filemanager/filemanager")
                        local fm = FileManager.instance
                        if fm and fm.file_dialog then UIManager:close(fm.file_dialog) end
                        self:convertList({ file })
                    end,
                } }
            end
        end)
    end
end

function CbzConverter:addToMainMenu(menu_items)
    menu_items.cbz_converter = {
        text = T("menu_title"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                -- Live-Fortschritt; antippen bietet Abbrechen an
                text_func = function() return Job.statusText() end,
                cbz_status = true,
                keep_menu_open = true,
                enabled_func = function() return Job.isRunning() end,
                callback = function() self:confirmCancel() end,
                separator = true,
            },
            { text = T("menu_file"), callback = function() self:chooseFile() end },
            { text = T("menu_folder"), callback = function() self:chooseFolder() end, separator = true },
            {
                text = T("about"),
                keep_menu_open = true,
                callback = function() UIManager:show(InfoMessage:new{ text = T("about_text") }) end,
            },
        },
    }
end

function CbzConverter:startPath()
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    return (fm and fm.file_chooser and fm.file_chooser.path) or require("datastorage"):getDataDir()
end

function CbzConverter:chooseFile()
    UIManager:show(PathChooser:new{
        select_directory = false,
        select_file = true,
        path = self:startPath(),
        file_filter = function(f) return Converter.SUPPORTED[ext_of(f)] end,
        onConfirm = function(path) self:convertList({ path }) end,
    })
end

function CbzConverter:chooseFolder()
    UIManager:show(PathChooser:new{
        select_directory = true,
        select_file = false,
        path = self:startPath(),
        onConfirm = function(dir)
            local list = {}
            local function scan(d)
                for name in lfs.dir(d) do
                    if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                        local p = d .. "/" .. name
                        local mode = lfs.attributes(p, "mode")
                        if mode == "directory" then
                            scan(p)
                        elseif mode == "file" and Converter.SUPPORTED[ext_of(p)] then
                            list[#list + 1] = p
                        end
                    end
                end
            end
            scan(dir)
            table.sort(list)
            if #list == 0 then
                UIManager:show(InfoMessage:new{ text = T("no_files") })
                return
            end
            UIManager:show(ConfirmBox:new{
                text = T("confirm_folder", #list),
                ok_text = T("start"),
                ok_callback = function() self:convertList(list) end,
            })
        end,
    })
end

-- Löscht nur Originale, deren CBZ nachweislich existiert und nicht leer ist
local function delete_originals(done)
    local deleted = 0
    for _, d in ipairs(done) do
        if (lfs.attributes(d.out, "size") or 0) > 0 and os.remove(d.src) then
            deleted = deleted + 1
        end
    end
    refresh_file_manager()
    UIManager:show(InfoMessage:new{ text = T("deleted", deleted) })
end

-- Zusammenfassung am Ende eines Laufs, erscheint ueber dem, was gerade offen ist (auch beim Lesen)
local function show_summary(r)
    refresh_file_manager()
    local lines = { T("done_title") }
    if #r.done == 1 and r.skip == 0 and #r.fail == 0 and not r.cancelled then
        local d = r.done[1]
        lines[#lines + 1] = T("done_one", d.out:match("([^/]+)$"), d.pages)
    else
        lines[#lines + 1] = T("sum_ok", #r.done)
        lines[#lines + 1] = T("sum_skip", r.skip)
        lines[#lines + 1] = T("sum_fail", #r.fail)
    end
    if r.cancelled then lines[#lines + 1] = T("sum_cancel") end
    for _, l in ipairs(r.fail) do lines[#lines + 1] = "• " .. l end
    for _, l in ipairs(r.notes) do lines[#lines + 1] = "• " .. l end
    if #r.done > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = T("delete_q", #r.done)
        UIManager:show(ConfirmBox:new{
            text = table.concat(lines, "\n"),
            ok_text = T("delete_ok"),
            cancel_text = T("delete_keep"),
            ok_callback = function() delete_originals(r.done) end,
        })
    else
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end
end

-- Ist das Menue des Konverters gerade offen, die Statuszeile neu zeichnen (Live-Fortschritt)
local function refresh_open_menu()
    for _, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, UI = pcall(require, mod)
        local ui = ok and UI.instance
        local container = ui and ui.menu and ui.menu.menu_container
        local menu = container and container[1]
        if menu and type(menu.item_table) == "table" and menu.updateItems and UIManager:isWidgetShown(container) then
            for _, item in ipairs(menu.item_table) do
                if type(item) == "table" and item.cbz_status then
                    menu:updateItems()
                    return
                end
            end
        end
    end
end

Job.on_change = refresh_open_menu
Job.on_finish = show_summary

function CbzConverter:convertList(list)
    if Job.add(list) then
        UIManager:show(InfoMessage:new{ text = T("started_bg"), timeout = 4 })
    else
        UIManager:show(InfoMessage:new{ text = T("queued"), timeout = 3 })
    end
end

function CbzConverter:confirmCancel()
    if not Job.isRunning() then return end
    UIManager:show(ConfirmBox:new{
        text = T("cancel_q", Job.currentName()),
        ok_text = T("abort"),
        cancel_text = T("continue"),
        ok_callback = function() Job.cancel() end,
    })
end

return CbzConverter
