-- Umwandlung im Hintergrund: jede Datei in einem eigenen Unterprozess, damit KOReader bedienbar bleibt.
-- Der Unterprozess schreibt seinen Fortschritt in eine kleine Datei, das Ergebnis kommt am Ende ueber
-- eine Pipe. Das Hauptprogramm schaut einmal pro Sekunde nach. Der Zustand gehoert dem Modul, nicht dem
-- Plugin, damit die Umwandlung weiterlaeuft, wenn man zwischen Bibliothek und Buch wechselt.
local DataStorage = require("datastorage")
local Converter = require("cbz_converter")
local T = require("cbz_i18n")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
require("ffi/posix_h")

local Job = {
    queue = {},       -- noch umzuwandelnde Dateien
    index = 0,        -- laufende Nummer der aktuellen Datei
    total = 0,        -- alle Dateien dieses Laufs
    child = nil,      -- { pid, fd, file, out, started }
    page = nil,       -- { current, total } der aktuellen Datei
    results = nil,    -- Sammlung fuer die Zusammenfassung
    on_change = nil,  -- wird bei jeder Aenderung aufgerufen (Menue neu zeichnen)
}

local POLL = 1
-- Eigener Unterordner: KOReader merkt sich beim Start alle Dateien direkt in cache/ und stuerzt beim
-- Schliessen eines Buchs ab, wenn eine davon inzwischen geloescht ist (doccache.lua, 11.11.2026).
local WORK_DIR = DataStorage:getDataDir() .. "/cache/cbzconverter"
local PROGRESS_FILE = WORK_DIR .. "/progress.txt"

local function out_of(src)
    return src:gsub("%.[^./]+$", "") .. ".cbz"
end

local function changed()
    if Job.on_change then pcall(Job.on_change) end
end

-- ── Wach bleiben ─────────────────────────────────────────────────────────────────────────────────
-- Waehrend der Umwandlung tippt oft niemand. Damit der E-Reader nicht nach der Einschlafzeit von selbst
-- einschlaeft, pausieren wir das (KOReaders eigener Schalter, Huelle/Knopf wirken weiter, das Dimmen auch).
-- Standby wuerde den Unterprozess anhalten, deshalb auch den verhindern.
local awake = false
local suspend_paused = false

local function keepAwake(on)
    if on == awake then return end
    awake = on
    local ok, PluginShare = pcall(require, "pluginshare")
    if on then
        UIManager:preventStandby()
        if ok and not PluginShare.pause_auto_suspend then
            PluginShare.pause_auto_suspend = true
            suspend_paused = true
        end
    else
        UIManager:allowStandby()
        -- Nur zuruecknehmen, was wir selbst gesetzt haben
        if ok and suspend_paused then PluginShare.pause_auto_suspend = false end
        suspend_paused = false
    end
end

-- ── Unterprozess ─────────────────────────────────────────────────────────────────────────────────
local function readProgress()
    local f = io.open(PROGRESS_FILE, "r")
    if not f then return end
    local current, total = f:read("*a"):match("^(%d+) (%d*)")
    f:close()
    if current then Job.page = { current = tonumber(current), total = tonumber(total) } end
end

local function startChild(file)
    require("util").makePath(WORK_DIR)
    os.remove(PROGRESS_FILE)
    local pid, fd = ffiutil.runInSubProcess(function(_pid, write_fd)
        local parent = ffi.C.getppid()
        local last = -1
        local count, err, note, out = Converter.convert(file, function(current, total)
            -- KOReader beendet: abbrechen, Converter raeumt .part und .tmp auf
            if ffi.C.getppid() ~= parent then return false end
            local now = os.time()
            if now ~= last then
                last = now
                local f = io.open(PROGRESS_FILE .. ".new", "w")
                if f then
                    f:write(string.format("%d %s", current, total or ""))
                    f:close()
                    os.rename(PROGRESS_FILE .. ".new", PROGRESS_FILE)
                end
            end
            return true
        end)
        ffiutil.writeToFD(write_fd, json.encode{ count = count, err = err, note = note, out = out }, true)
    end, true)
    if not pid then return false end
    Job.child = { pid = pid, fd = fd, file = file, out = out_of(file) }
    Job.page = nil
    return true
end

local function record(file, result)
    local name = file:match("([^/]+)$")
    local r = Job.results
    if result.count then
        r.done[#r.done + 1] = { src = file, out = result.out, pages = result.count }
        if result.note then r.notes[#r.notes + 1] = name .. ": " .. result.note end
    elseif result.note == "skip" then
        r.skip = r.skip + 1
    else
        r.fail[#r.fail + 1] = name .. ": " .. tostring(result.err or T("err_unknown"))
    end
end

local poll

local function finish()
    if Job.poll_task then UIManager:unschedule(Job.poll_task) end
    Job.poll_task = nil
    Job.child = nil
    Job.page = nil
    os.remove(PROGRESS_FILE)
    keepAwake(false)
    local results = Job.results
    Job.results = nil
    Job.queue = {}
    changed()
    if Job.on_finish then Job.on_finish(results) end
end

local function next_file()
    while #Job.queue > 0 do
        local file = table.remove(Job.queue, 1)
        Job.index = Job.index + 1
        changed()
        if startChild(file) then
            Job.poll_task = poll
            UIManager:scheduleIn(POLL, poll)
            return
        end
        record(file, { err = T("err_start") })
    end
    finish()
end

poll = function()
    Job.poll_task = nil
    local child = Job.child
    if not child then return end
    readProgress()
    local has_data = ffiutil.getNonBlockingReadSize(child.fd) ~= 0
    local done = not has_data and ffiutil.isSubProcessDone(child.pid)
    if done then has_data = ffiutil.getNonBlockingReadSize(child.fd) ~= 0 end
    if has_data or done then
        local raw = has_data and ffiutil.readAllFromFD(child.fd) or nil
        if not has_data then ffiutil.readAllFromFD(child.fd) end
        if has_data then ffiutil.isSubProcessDone(child.pid, true) end
        local ok, result = pcall(json.decode, raw or "")
        if not (ok and type(result) == "table") then
            -- Unterprozess ohne Antwort beendet (z. B. zu wenig Speicher)
            logger.warn("CbzConverter: conversion process ended without result", child.file)
            os.remove(child.out .. ".part")
            result = { err = T("err_crash") }
        end
        if result.err == json.null then result.err = nil end
        if result.note == json.null then result.note = nil end
        Job.child = nil
        record(child.file, result)
        next_file()
        return
    end
    changed()
    Job.poll_task = poll
    UIManager:scheduleIn(POLL, poll)
end

-- ── Oeffentlich ──────────────────────────────────────────────────────────────────────────────────
function Job.isRunning()
    return Job.results ~= nil
end

--- Dateien umwandeln. Laeuft schon etwas, kommen sie hinten an die Warteschlange.
-- @return true, wenn ein neuer Lauf gestartet wurde; false, wenn angehaengt
function Job.add(list)
    local seen = {}
    if Job.child then seen[Job.child.file] = true end
    for _, f in ipairs(Job.queue) do seen[f] = true end
    local added = 0
    for _, f in ipairs(list) do
        if not seen[f] then
            Job.queue[#Job.queue + 1] = f
            seen[f] = true
            added = added + 1
        end
    end
    if Job.isRunning() then
        Job.total = Job.total + added
        changed()
        return false
    end
    Job.results = { done = {}, fail = {}, notes = {}, skip = 0, cancelled = false }
    Job.index, Job.total = 0, #Job.queue
    keepAwake(true)
    next_file()
    return true
end

--- Laufende Umwandlung und Warteschlange abbrechen. Die unfertige CBZ wird geloescht.
function Job.cancel()
    if not Job.isRunning() then return end
    local child = Job.child
    if child then
        ffiutil.terminateSubProcess(child.pid)
        pcall(ffiutil.readAllFromFD, child.fd)
        os.remove(child.out .. ".part")
        local tmp = child.out .. ".tmp"
        if lfs.attributes(tmp, "mode") == "directory" then
            for name in lfs.dir(tmp) do
                if name ~= "." and name ~= ".." then os.remove(tmp .. "/" .. name) end
            end
            lfs.rmdir(tmp)
        end
    end
    Job.results.cancelled = true
    finish()
end

--- Statuszeile fuers Menue
function Job.statusText()
    if not Job.isRunning() then return T("status_idle") end
    local page = Job.page
    if page and page.total then
        return T("status_page", Job.index, Job.total, page.current, page.total)
    elseif page then
        return T("status_image", Job.index, Job.total, page.current)
    end
    return T("status_file", Job.index, Job.total)
end

function Job.currentName()
    return Job.child and Job.child.file:match("([^/]+)$") or ""
end

return Job
