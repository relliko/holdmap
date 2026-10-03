--[[
* holdmap
*
* Shows the zone map while a key is held (Shift+M by default) and closes it when the key is let
* go (or, in toggle mode, on the next press): pressing runs /map, and closing presses Escape for the game, but only while the game's
* map menu is open. It never presses any other key, and offers no way to send keys of your
* choosing.
*
* Nothing is ever sent to the server beyond what /map and Escape do themselves.
--]]

addon.name    = 'holdmap';
addon.author  = 'Relli';
addon.version = '0.2';
addon.desc    = 'Shows the map while a key is held (or toggles it) and closes it on release.';
addon.link    = '';

require('common');
local ffi      = require('ffi');
local chat     = require('chat');
local settings = require('settings');
local core     = require('core');
local safemem  = require('safemem');

local defaults = T{
    key = 'M',
    mod = 'shift',
    mode = 'hold',
};

local hm = {
    settings = settings.load(defaults),
    s = nil,
    vk = 0,
    mod_held = false,
};

local function keyboard()
    return AshitaCore:GetInputManager():GetKeyboard();
end

-- Builds the state machine from the settings; false when the key name isn't one Ashita knows.
local function apply()
    local dik = keyboard():S2D(hm.settings.key);
    if (dik == nil or dik <= 0 or dik > 0xFF or dik == core.DIK_ESCAPE) then
        return false;
    end
    if (core.MODS[hm.settings.mod] == nil) then
        hm.settings.mod = 'shift';
    end
    if (hm.settings.mode ~= 'toggle') then
        hm.settings.mode = 'hold';
    end
    hm.s = core.new(dik, hm.settings.mod, hm.settings.mode);
    hm.vk = keyboard():D2V(dik) or 0;
    return true;
end

local function bind_name()
    local mod = hm.settings.mod;
    return (mod == 'none' and '' or mod:gsub('^%l', string.upper) .. '+') .. hm.settings.key:upper();
end

--[[
* The game's current menu name, or '' (read only; same pointer path as HXUI's GetMenuName).
* Each hop is read with safemem: a menu freed mid-read gives '' instead of a crash.
--]]
local menu_ptr = nil;
local function menu_name()
    if (menu_ptr == nil) then
        menu_ptr = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0) or 0;
    end
    if (menu_ptr == 0) then
        return '';
    end
    local sub = safemem.u32(menu_ptr);
    local value = sub ~= nil and sub ~= 0 and safemem.u32(sub) or nil;
    local header = value ~= nil and value ~= 0 and safemem.u32(value + 4) or nil;
    local name = header ~= nil and header ~= 0 and safemem.read(header + 0x46, 16) or nil;
    return name ~= nil and (name:gsub('%z', '')) or '';
end

local function map_open()
    local name = menu_name();
    return name:find('map0', 1, true) ~= nil or name:find('maplist', 1, true) ~= nil;
end

ashita.events.register('load', 'holdmap_load', function ()
    if (not apply()) then
        hm.settings.key, hm.settings.mod, hm.settings.mode = defaults.key, defaults.mod, defaults.mode;
        apply();
    end
end);

ashita.events.register('unload', 'holdmap_unload', function ()
    settings.save();
end);

settings.register('settings', 'holdmap_settings_update', function (s)
    if (s ~= nil) then
        hm.settings = s;
    end
    apply();
end);

--[[
* event: key_state
* desc : The game's DirectInput keyboard poll; e.data_raw is the 256-byte key-state buffer.
--]]
ashita.events.register('key_state', 'holdmap_key_state', function (e)
    if (hm.s == nil) then
        return;
    end
    local buf = ffi.cast('uint8_t*', e.data_raw);
    local chat_open = AshitaCore:GetChatManager():IsInputOpen() ~= 0;
    local mods = core.MODS[hm.s.mod];
    hm.mod_held = #mods == 0;
    for _, k in ipairs(mods) do
        hm.mod_held = hm.mod_held or buf[k] ~= 0;
    end
    if (core.step(hm.s, buf, map_open(), chat_open, os.clock()) == 'open') then
        AshitaCore:GetChatManager():QueueCommand(1, '/map');
    end
end);

--[[
* event: key
* desc : Window keyboard messages. The chord's key is kept from Ashita's binds and the game here
*        too, so holding it only shows the map.
--]]
ashita.events.register('key', 'holdmap_key', function (e)
    if (hm.s == nil or e.wparam ~= hm.vk) then
        return;
    end
    if (hm.s.state == 'holding' or hm.s.hide_key
        or (hm.mod_held and AshitaCore:GetChatManager():IsInputOpen() == 0)) then
        e.blocked = true;
    end
end);

ashita.events.register('command', 'holdmap_command', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/holdmap')) then
        return;
    end
    e.blocked = true;

    if (#args >= 3 and args[2]:any('key')) then
        local old = hm.settings.key;
        hm.settings.key = args[3];
        if (not apply()) then
            hm.settings.key = old;
            apply();
            print(chat.header(addon.name):append(chat.error('Unknown key: ' .. args[3])));
            return;
        end
        settings.save();
    elseif (#args >= 3 and args[2]:any('mod')) then
        if (core.MODS[args[3]:lower()] == nil) then
            print(chat.header(addon.name):append(chat.error('Modifier must be shift, ctrl, alt or none.')));
            return;
        end
        hm.settings.mod = args[3]:lower();
        apply();
        settings.save();
    elseif (#args >= 2 and args[2]:any('mode', 'toggle', 'hold')) then
        local mode = args[2]:lower();
        if (mode == 'mode') then
            mode = (args[3] or ''):lower();
            if (mode == '') then
                mode = hm.settings.mode == 'toggle' and 'hold' or 'toggle';
            end
        end
        if (mode ~= 'hold' and mode ~= 'toggle') then
            print(chat.header(addon.name):append(chat.error('Mode must be hold or toggle.')));
            return;
        end
        hm.settings.mode = mode;
        apply();
        settings.save();
    elseif (#args >= 2) then
        print(chat.header(addon.name):append(chat.message('/holdmap key <key>  |  /holdmap mod <shift|ctrl|alt|none>  |  /holdmap mode <hold|toggle>')));
        return;
    end
    local verb, rest = 'Hold ', ' to show the map.';
    if (hm.settings.mode == 'toggle') then
        verb, rest = 'Press ', ' to open or close the map.';
    end
    print(chat.header(addon.name):append(chat.message(verb)):append(chat.success(bind_name())):append(chat.message(rest)));
end);
