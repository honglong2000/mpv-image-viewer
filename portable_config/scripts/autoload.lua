-- autoload.lua: Industrial-Grade Windows Sort (13,000+ Items)
-- Uses shlwapi.dll!StrCmpLogicalW and loadlist for stability.

local utils = require 'mp.utils'
local options = require 'mp.options'
local ffi = require 'ffi'

-- 1. LOAD WINDOWS API
local shlwapi, kernel32
local success = pcall(function()
    ffi.cdef[[
        int StrCmpLogicalW(const wchar_t *psz1, const wchar_t *psz2);
        int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr, int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
    ]]
    shlwapi = ffi.load("shlwapi.dll")
    kernel32 = ffi.load("kernel32.dll")
end)

local o = { disabled = false, images = true, videos = true, audio = true }
options.read_options(o, "autoload")

-- Extension setup
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
create_extensions()

-- 2. WINDOWS ENCODING & SORT
local function to_utf16(str)
    local CP_UTF8 = 65001
    local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, #str, nil, 0)
    local buf = ffi.new("wchar_t[?]", len + 1)
    kernel32.MultiByteToWideChar(CP_UTF8, 0, str, #str, buf, len)
    buf[len] = 0
    return buf
end

local function alphanumsort(filenames)
    if not shlwapi then return end
    table.sort(filenames, function(a, b)
        -- Native Windows Logical Comparison
        return shlwapi.StrCmpLogicalW(to_utf16(a), to_utf16(b)) < 0
    end)
end

-- 3. MASSIVE FOLDER LOGIC
local last_dir = nil

local function sync_large_folder()
    local path = mp.get_property("path", "")
    if path == "" or o.disabled then return end
    
    local dir, filename = utils.split_path(path)
    if dir == last_dir then return end
    last_dir = dir

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

    -- Build a temporary playlist file to handle 13,000 items efficiently
    local tmp_path = os.getenv("TEMP") .. "\\mpv_playlist.m3u8"
    local f = io.open(tmp_path, "w")
    if not f then return end
    
    local start_idx = 0
    for i, file_name in ipairs(filtered) do
        f:write(utils.join_path(dir, file_name) .. "\n")
        if file_name == filename then start_idx = i - 1 end
    end
    f:close()

    -- Load the playlist file and jump to the current file's index
    mp.commandv("loadlist", tmp_path, "replace")
    mp.set_property_number("playlist-pos", start_idx)
end

mp.register_event("file-loaded", sync_large_folder)