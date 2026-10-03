--[[
* holdmap - core
* The hold / release state machine, kept free of Ashita so it can be tested on its own.
*
* step() runs once per DirectInput keyboard poll with the game's key-state buffer (256 bytes,
* indexed by DIK scan code, 0x80 = down) and what the game is showing. It returns what the addon
* should do this poll ('open' to run /map), and writes into the buffer itself: it hides the bound
* key from the game while the chord is held, and presses Escape only while the game's map menu is
* open. Escape is the one key it ever presses, and nothing outside this file can ask for another.
--]]

local core = {};

local DIK_ESCAPE = 0x01;
local MODS = {
    shift = { 0x2A, 0x36 },
    ctrl  = { 0x1D, 0x9D },
    alt   = { 0x38, 0xB8 },
    none  = {},
};

local ESC_FRAMES  = 2;   -- polls Escape is held down for
local SETTLE      = 6;   -- polls to wait after a press before looking at the menu again
local MAX_PRESSES = 3;   -- Escape presses per release, in case one is missed
local OPEN_WAIT   = 1.0; -- seconds a release waits for a map that /map hasn't shown yet

core.MODS = MODS;
core.DIK_ESCAPE = DIK_ESCAPE;

function core.new(key, mod)
    return {
        key = key,          -- DIK scan code of the bound key
        mod = mod,          -- 'shift', 'ctrl', 'alt' or 'none'
        state = 'idle',     -- 'idle', 'holding', 'closing'
        hide_key = false,   -- hide the bound key from the game until it is let go
        esc_left = 0,       -- polls of Escape still to hold down
        settle = 0,         -- polls still to wait after a press
        presses = 0,
        deadline = 0,
    };
end

local function down(buf, k) return buf[k] ~= 0; end

local function mod_down(s, buf)
    local keys = MODS[s.mod] or MODS.shift;
    if (#keys == 0) then
        return true;
    end
    for _, k in ipairs(keys) do
        if (down(buf, k)) then
            return true;
        end
    end
    return false;
end

--[[
* buf      : key-state buffer (indexable 0-255, writable)
* map_open : the game's map menu is up
* chat_open: the chat line is open (the chord is ignored so the key can be typed)
* now      : seconds
* Returns 'open' when /map should be run, else nil.
--]]
function core.step(s, buf, map_open, chat_open, now)
    local key_down = down(buf, s.key);
    local chord = key_down and mod_down(s, buf) and not chat_open;
    local action = nil;

    if (chord and s.state ~= 'holding') then
        -- A fresh press, or a press again while a release is still closing the map.
        if (not map_open) then
            action = 'open';
        end
        s.state = 'holding';
        s.hide_key = true;
        s.esc_left, s.settle, s.presses = 0, 0, 0;
    elseif (not chord and s.state == 'holding') then
        s.state = 'closing';
        s.deadline = now + OPEN_WAIT;
        s.presses = 0;
    end

    if (s.hide_key) then
        if (key_down) then
            buf[s.key] = 0;
        else
            s.hide_key = false;
        end
    end

    if (s.state == 'closing') then
        if (s.esc_left > 0) then
            buf[DIK_ESCAPE] = 0x80;
            s.esc_left = s.esc_left - 1;
            if (s.esc_left == 0) then
                s.settle = SETTLE;
            end
        elseif (s.settle > 0) then
            s.settle = s.settle - 1;
        elseif (map_open and s.presses < MAX_PRESSES) then
            buf[DIK_ESCAPE] = 0x80;
            s.esc_left = ESC_FRAMES - 1;
            s.presses = s.presses + 1;
            if (s.esc_left == 0) then
                s.settle = SETTLE;
            end
        elseif (map_open or s.presses > 0 or now >= s.deadline) then
            -- Closed, or given up on: never keep pressing Escape at a menu that won't go.
            s.state = 'idle';
        end
    end

    return action;
end

return core;
