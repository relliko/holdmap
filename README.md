# holdmap

Ashita v4 addon: hold **Shift+M** to show the zone map, let go to close it. Or switch to toggle
mode (`/holdmap mode toggle`): press once to open, press again to close.

- Pressing the chord runs `/map` (unless the map is already up).
- Letting go presses Escape for the game, but only while the game's map menu (`map0` / `maplist`)
  is open, and at most three times. If the map never appears within a second, nothing is pressed.
- The bound key is hidden from the game and from Ashita binds while the chord is held. With the
  chat line open the chord is ignored, so the letter can still be typed.

Escape is the only key it ever presses, written into the game's DirectInput key-state buffer from
the `key_state` event. There is no command or API for sending other keys.

## Commands

    /addon load holdmap
    /holdmap                       show the current bind
    /holdmap key <key>             e.g. /holdmap key N (any Ashita key name except Escape)
    /holdmap mod <shift|ctrl|alt|none>
    /holdmap mode <hold|toggle>    no argument switches between the two

## Tests

    python tests/test_core.py      state machine, under LuaJIT via lupa
    python -c "from lupa import luajit21; r=luajit21.LuaRuntime(); r.execute(\"package.path='./?.lua;'..package.path\"); r.execute(open('tests/smoke.lua').read())"
