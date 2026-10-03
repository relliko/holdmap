-- Loads holdmap.lua against stubbed Ashita globals and drives each event once.
local events, queued, printed = {}, {}, {}
addon = {}
ashita = {
    events = { register = function (name, _, fn) events[name] = fn end },
    memory = { find = function () return 0 end },
}
local kb = {
    S2D = function (_, s) local t = { M = 0x32, m = 0x32, N = 0x31, ESCAPE = 0x01 } return t[s] or -1 end,
    D2V = function (_, d) return ({ [0x32] = 0x4D, [0x31] = 0x4E })[d] or 0 end,
}
local input_open = 0
AshitaCore = {
    GetInputManager = function () return { GetKeyboard = function () return kb end } end,
    GetChatManager = function () return {
        IsInputOpen = function () return input_open end,
        QueueCommand = function (_, mode, cmd) queued[#queued + 1] = cmd end,
    } end,
}
function T(t) return t end
string.args = function (s) local a = {} for w in s:gmatch('%S+') do a[#a + 1] = w end return a end
string.any = function (s, ...) for _, v in ipairs({ ... }) do if s == v then return true end end return false end
local function chain() local o = {} o.append = function () return o end return o end
package.loaded['common'] = true
package.loaded['chat'] = { header = chain, message = chain, error = chain, success = chain }
local saved = 0
package.loaded['settings'] = { load = function (d) return { key = d.key, mod = d.mod } end,
    save = function () saved = saved + 1 end, register = function () end }
print = function (...) printed[#printed + 1] = true end

dofile('holdmap.lua')
events.load()
local ffi = require('ffi')
local buf = ffi.new('uint8_t[256]')
buf[0x2A], buf[0x32] = 0x80, 0x80
events.key_state({ data_raw = buf })
assert(queued[1] == '/map', 'expected /map')
assert(buf[0x32] == 0, 'M should be hidden')
local e = { wparam = 0x4D, lparam = 0 }
events.key(e)
assert(e.blocked, 'M window message should be blocked while holding')
local c = { command = '/holdmap key N' } events.command(c)
assert(c.blocked and saved == 1)
c = { command = '/holdmap key ZZZ' } events.command(c)
c = { command = '/holdmap mod ctrl' } events.command(c)
c = { command = '/holdmap mod bogus' } events.command(c)
c = { command = '/holdmap mode toggle' } events.command(c)
c = { command = '/holdmap mode bogus' } events.command(c)
c = { command = '/holdmap mode' } events.command(c)
c = { command = '/holdmap toggle' } events.command(c)
c = { command = '/holdmap' } events.command(c)
c = { command = '/other' } events.command(c)
assert(not c.blocked)
events.unload()
io.write('smoke ok\n')
