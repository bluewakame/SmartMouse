"""接続通知の判断ロジックのテスト。

他人のPCでこっそり動かされることを防ぐための通知なので、
「繋がったのに黙っている」状態を作らないことを固定する。
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from connection_watch import ConnectionWatcher


class ConnectionWatcherTests(unittest.TestCase):
    def setUp(self) -> None:
        self.watcher = ConnectionWatcher(quiet_seconds=60.0)

    def test_notifies_when_a_phone_connects(self) -> None:
        self.assertTrue(self.watcher.update(True, now=100.0))

    def test_stays_quiet_while_still_connected(self) -> None:
        self.watcher.update(True, now=100.0)
        for offset in (0.5, 1.0, 300.0):
            with self.subTest(offset=offset):
                self.assertFalse(self.watcher.update(True, now=100.0 + offset))

    def test_stays_quiet_when_nothing_is_connected(self) -> None:
        self.assertFalse(self.watcher.update(False, now=100.0))

    def test_stays_quiet_on_disconnect(self) -> None:
        self.watcher.update(True, now=100.0)
        self.assertFalse(self.watcher.update(False, now=101.0))

    def test_reconnect_soon_after_does_not_notify_again(self) -> None:
        # Wi-Fiが不安定だとクライアントが自動再接続を繰り返す。
        self.watcher.update(True, now=100.0)
        self.watcher.update(False, now=101.0)
        self.assertFalse(self.watcher.update(True, now=102.0))

    def test_reconnect_after_the_quiet_period_notifies(self) -> None:
        # 十分に時間が空いていれば、別の接続として知らせる。
        self.watcher.update(True, now=100.0)
        self.watcher.update(False, now=101.0)
        self.assertTrue(self.watcher.update(True, now=200.0))

    def test_first_connection_is_never_suppressed(self) -> None:
        # 起動直後に繋がれた場合こそ知らせる必要がある。
        watcher = ConnectionWatcher(quiet_seconds=3600.0)
        self.assertTrue(watcher.update(True, now=0.0))

    def test_connected_property_tracks_state(self) -> None:
        self.assertFalse(self.watcher.connected)
        self.watcher.update(True, now=1.0)
        self.assertTrue(self.watcher.connected)
        self.watcher.update(False, now=2.0)
        self.assertFalse(self.watcher.connected)


if __name__ == "__main__":
    unittest.main()
