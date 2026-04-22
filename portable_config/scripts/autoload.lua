-- autoload.lua: Final Stabilized Windows 11 Sort & Sync
-- Fixes the (21) -> (19) loop by locking the playlist direction.

local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    disabled = false,
    images = true,
    videos = true,
    audio = true,
    additional_image_exts = "",
    additional_video_exts = "",
    additional_audio_exts = "",
    ignore_hidden = true,
    same_type = false,
    directory_mode = "auto",
    ignore_patterns = ""
}

local function Set(t)
    local set = {}
    for _, v in pairs(t) do set[v] = true end
    return set
end

local EXT_VIDEO = Set{'3g2', '3gp', 'avi', 'flv', 'm2ts', 'm4v', 'mj2', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'ogv', 'rmvb', 'webm', 'wmv', 'y4m'}
local EXT_AUDIO = Set{'aiff', 'ape', 'au', 'flac', 'm4a', 'mka', 'mp3', 'oga', 'ogg', 'ogm', 'opus', 'wav', 'wma'}
local EXT_IMAGE = Set{'avif', 'bmp', 'gif', 'j2k', 'jp2', 'jpeg', 'jpg', 'jxl', 'png', 'svg', 'tga', 'tif', 'tiff', 'webp'}

local ALL_EXTS = {}

local function create_extensions()
    ALL_EXTS = {}
    if o.videos then for k in pairs(EXT_VIDEO) do ALL_EXTS[k] = true end end
    if o.audio then for k in pairs(EXT_AUDIO) do ALL_EXTS[k] = true end end
    if o.images then for k in pairs(EXT_IMAGE) do ALL_EXTS[k] = true end end
end

options.read_options(o, "autoload")
create_extensions()

-- WINDOWS 11 LOGICAL SORT EMULATION
local function make_sort_key(s)
    if not s then return "" end
    local key = s:lower()
    
    -- Replace hyphens with high-value symbols to push them after numbers
    key = key:gsub("%-", "~~")
    
    -- Pad numbers and append length to handle 000 vs 0
    key = key:gsub("%d+", function(n)
        return string.format("%012d", tonumber(n)) .. string.format("%03d", #n)
    end)
    
    return key
end

local function alphanumsort(filenames)
    table.sort(filenames, function(a, b)
        return make_sort_key(a) < make_sort_key(b)
    end)
end

local function find_and_add_entries()
    local path = mp.get_property("path", "")
    if path == "" or o.disabled then return end
    
    local dir, filename = utils.split_path(path)
    local files = utils.readdir(dir, "files")
    if not files then return end

    local filtered = {}
    for _, f in ipairs(files) do
        local ext = f:match("%.([^%.]+)$")
        if ext and ALL_EXTS[ext:lower()] then
            table.insert(filtered, f)
        end
    end

    alphanumsort(filtered)

    local current_idx
    for i, f in ipairs(filtered) do
        if f == filename then current_idx = i break end
    end

    if not current_idx then return end

    local pl_count = mp.get_property_number("playlist-count", 0)
    local pl_pos = mp.get_property_number("playlist-pos", 0)
    
    -- DIRECTIONAL SYNC: This stops the (21) -> (19) loop.
    -- If we only have 1 file, load both neighbors to start.
    if pl_count <= 1 then
        if filtered[current_idx + 1] then
            mp.commandv("loadfile", utils.join_path(dir, filtered[current_idx + 1]), "append")
        end
        if filtered[current_idx - 1] then
            mp.commandv("loadfile", utils.join_path(dir, filtered[current_idx - 1]), "append")
            mp.commandv("playlist-move", mp.get_property_number("playlist-count", 1) - 1, 0)
        end
    -- If we are scrolling FORWARD (at the end of the current playlist), 
    -- ONLY add the next file. Never look back.
    elseif pl_pos == pl_count - 1 then
        if filtered[current_idx + 1] then
            mp.commandv("loadfile", utils.join_path(dir, filtered[current_idx + 1]), "append")
        end
    end
end

mp.register_event("start-file", find_and_add_entries)