"""Tests for holdmap's hold / release state machine (core.lua), run under LuaJIT via lupa.

    python tests/test_core.py
"""
import os
import unittest

from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)

DIK_ESCAPE, DIK_M, DIK_LSHIFT, DIK_LCTRL = 0x01, 0x32, 0x2A, 0x1D


class Game:
    """A fake game: a fresh key buffer each poll, and a map menu that /map opens and Escape closes."""

    def __init__(self, mod='shift', open_delay=2, esc_closes=True, mode='hold'):
        self.lua = luajit21.LuaRuntime()
        self.lua.execute(f"package.path = [[{ADDON}]] .. '/?.lua;' .. package.path")
        self.core = self.lua.eval("require('core')")
        self.s = self.core.new(DIK_M, mod, mode)
        self.new_buf = self.lua.eval("function () return require('ffi').new('uint8_t[256]') end")
        self.set = self.lua.eval("function (b, k, v) b[k] = v end")
        self.get = self.lua.eval("function (b, k) return b[k] end")
        self.held = set()
        self.map_open = False
        self.chat_open = False
        self.open_in = None
        self.open_delay = open_delay
        self.esc_closes = esc_closes
        self.esc_was_down = False
        self.now = 0.0
        self.opens = 0
        self.esc_presses = 0
        self.seen_m = []

    def poll(self, n=1):
        for _ in range(n):
            buf = self.new_buf()
            for k in self.held:
                self.set(buf, k, 0x80)
            action = self.core.step(self.s, buf, self.map_open, self.chat_open, self.now)
            if action == 'open':
                self.opens += 1
                self.open_in = self.open_delay
            # What the game sees this poll.
            self.seen_m.append(self.get(buf, DIK_M) != 0)
            esc = self.get(buf, DIK_ESCAPE) != 0
            if esc and not self.esc_was_down:
                self.esc_presses += 1
                if self.esc_closes:
                    self.map_open = False
            self.esc_was_down = esc
            if self.open_in is not None:
                self.open_in -= 1
                if self.open_in <= 0:
                    self.map_open, self.open_in = True, None
            self.now += 1 / 60


class CoreTests(unittest.TestCase):
    def test_hold_opens_and_release_closes(self):
        g = Game()
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(30)
        self.assertEqual(g.opens, 1)
        self.assertTrue(g.map_open)
        self.assertFalse(any(g.seen_m), 'M reached the game while the chord was held')
        g.held = set()
        g.poll(30)
        self.assertFalse(g.map_open)
        self.assertEqual(g.esc_presses, 1)
        self.assertEqual(g.s.state, 'idle')

    def test_quick_tap_closes_once_map_appears(self):
        g = Game(open_delay=10)
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(1)
        g.held = set()
        g.poll(40)
        self.assertEqual(g.opens, 1)
        self.assertFalse(g.map_open)
        self.assertEqual(g.esc_presses, 1)

    def test_no_escape_when_map_never_opens(self):
        g = Game(open_delay=10_000)
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(5)
        g.held = set()
        g.poll(120)
        self.assertEqual(g.esc_presses, 0)
        self.assertEqual(g.s.state, 'idle')

    def test_gives_up_on_a_map_that_wont_close(self):
        g = Game(esc_closes=False)
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(10)
        g.held = set()
        g.poll(200)
        self.assertEqual(g.esc_presses, 3)
        self.assertEqual(g.s.state, 'idle')

    def test_m_alone_and_chat_open_do_nothing(self):
        g = Game()
        g.held = {DIK_M}
        g.poll(10)
        self.assertEqual(g.opens, 0)
        self.assertTrue(all(g.seen_m), 'plain M should still reach the game')
        g.held = set()
        g.poll(2)
        g.chat_open = True
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(10)
        self.assertEqual(g.opens, 0)
        self.assertEqual(g.esc_presses, 0)

    def test_map_already_open_is_not_reopened_but_closes(self):
        g = Game()
        g.map_open = True
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(10)
        self.assertEqual(g.opens, 0)
        g.held = set()
        g.poll(20)
        self.assertFalse(g.map_open)

    def test_shift_released_first_keeps_m_hidden_until_let_go(self):
        g = Game()
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(10)
        g.held = {DIK_M}
        g.poll(10)
        self.assertFalse(any(g.seen_m))
        self.assertFalse(g.map_open)
        g.held = set()
        g.poll(5)
        g.held = {DIK_M}
        g.poll(1)
        self.assertTrue(g.seen_m[-1])

    def test_repress_while_closing_holds_again(self):
        g = Game()
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(10)
        g.held = set()
        g.poll(1)  # the release poll presses Escape
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(20)
        self.assertTrue(g.map_open)
        self.assertEqual(g.s.state, 'holding')
        g.held = set()
        g.poll(20)
        self.assertFalse(g.map_open)

    def test_ctrl_modifier(self):
        g = Game(mod='ctrl')
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(5)
        self.assertEqual(g.opens, 0)
        g.held = {DIK_LCTRL, DIK_M}
        g.poll(5)
        self.assertEqual(g.opens, 1)


    def tap(self_, g, polls_after=20):
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(3)
        g.held = set()
        g.poll(polls_after)

    def test_toggle_press_opens_press_again_closes(self):
        g = Game(mode='toggle')
        self.tap(g)
        self.assertTrue(g.map_open, 'map should stay open after release in toggle mode')
        self.assertEqual(g.esc_presses, 0)
        self.tap(g)
        self.assertFalse(g.map_open)
        self.assertEqual(g.esc_presses, 1)
        self.assertEqual(g.opens, 1)
        self.tap(g)
        self.assertTrue(g.map_open)
        self.assertEqual(g.opens, 2)
        self.assertFalse(any(g.seen_m))

    def test_toggle_holding_does_not_repeat(self):
        g = Game(mode='toggle')
        g.held = {DIK_LSHIFT, DIK_M}
        g.poll(120)
        self.assertEqual(g.opens, 1)
        self.assertTrue(g.map_open)
        self.assertEqual(g.esc_presses, 0)

    def test_toggle_second_press_before_map_shows_closes_it(self):
        g = Game(mode='toggle', open_delay=15)
        self.tap(g, polls_after=1)
        self.tap(g, polls_after=60)
        self.assertEqual(g.opens, 1)
        self.assertFalse(g.map_open)
        self.assertEqual(g.esc_presses, 1)

    def test_toggle_closes_a_map_opened_by_hand(self):
        g = Game(mode='toggle')
        g.map_open = True
        self.tap(g)
        self.assertFalse(g.map_open)
        self.assertEqual(g.opens, 0)


if __name__ == '__main__':
    unittest.main()
