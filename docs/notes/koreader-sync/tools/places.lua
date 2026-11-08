-- ./luajit places.lua <book> <out-prefix> [xpointers-file], from KOReader's install
-- folder (run.sh). Uses KOReader's own Lua API; nothing of it is copied here.
-- Writes KOReader's own xpointers every few pages (<out>-ko.tsv), and, given a
-- file of xpointers, where each lands (<out>-landed.tsv).
require("setupkoenv")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
G_reader_settings = LuaSettings:open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_defaults = require("luadefaults"):open()
require("ffi/framebuffer").dummy = true
local Device = require("device")
require("document/canvascontext"):init(Device)
local DocumentRegistry = require("document/documentregistry")

local path, out, input = arg[1], arg[2], arg[3]
local doc = DocumentRegistry:openDocument(path)
doc:loadDocument()
doc:render()
local pages = doc:getPageCount()

local function clean(text)
    return (tostring(text or ""):gsub("[\t\r\n]", " "))
end

-- The words from `xp` on, as KOReader reads them (getTextFromXPointer
-- returns the whole node and ignores the offset).
local function textAt(xp)
    local last = xp
    for _ = 1, 8 do
        local nextEnd = doc:getNextVisibleWordEnd(last)
        if not nextEnd then break end
        last = nextEnd
    end
    return doc:getTextFromXPointers(xp, last, false) or ""
end

-- KOReader's own places: what it would push from each page.
local ko = io.open(out .. "-ko.tsv", "w")
ko:write("page\tpages\txpointer\ttext\n")
for page = 1, pages, 3 do
    doc:gotoPage(page)
    local xp = doc:getXPointer()
    ko:write(string.format("%d\t%d\t%s\t%s\n", page, pages, xp, clean(textAt(xp))))
end
ko:close()

-- Where Octavo's places would land.
if input then
    local landed = io.open(out .. "-landed.tsv", "w")
    landed:write("id\tvalid\tpage\tpages\ttext\tnormal\n")
    for line in io.lines(input) do
        local id, xp = line:match("^([^\t]+)\t(.+)$")
        if id then
            local valid = doc:isXPointerInDocument(xp) and true or false
            local page = valid and doc:getPageFromXPointer(xp) or 0
            local text = valid and clean(textAt(xp)) or ""
            local normal = valid and tostring(doc:getNormalizedXPointer(xp)) or ""
            landed:write(string.format("%s\t%s\t%d\t%d\t%s\t%s\n", id, tostring(valid), page, pages, text, normal))
        end
    end
    landed:close()
end
doc:close()
print("done", path, pages)
