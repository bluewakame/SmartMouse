"""QRコードへ載せるLANアドレスの選び方のテスト。

``0.0.0.0`` や ``127.0.0.1`` を載せたQRは、読み取れてもスマホからは
絶対に繋がらない。そういうアドレスを選ばないことを固定する。
"""

import socket
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import lan


class UsableLanIPTests(unittest.TestCase):
    def test_private_addresses_are_usable(self) -> None:
        for address in ("192.168.1.5", "10.0.0.2", "172.16.3.4"):
            with self.subTest(address=address):
                self.assertTrue(lan.is_usable_lan_ip(address))

    def test_addresses_a_phone_can_never_reach_are_rejected(self) -> None:
        # 0.0.0.0 は経路が無いときに getsockname() が返しうる。
        # 169.254.x.x はDHCPに失敗した状態で、同じLANでも繋がらないことが多い。
        for address in ("0.0.0.0", "127.0.0.1", "127.0.0.53", "169.254.10.20"):
            with self.subTest(address=address):
                self.assertFalse(lan.is_usable_lan_ip(address))

    def test_garbage_is_rejected(self) -> None:
        for address in ("", "localhost", "::1", "999.1.1.1", "192.168.1"):
            with self.subTest(address=address):
                self.assertFalse(lan.is_usable_lan_ip(address))


class FindLanIPTests(unittest.TestCase):
    def test_returns_none_when_only_unusable_addresses_exist(self) -> None:
        with mock.patch.object(lan, "candidate_lan_ips", return_value=[]):
            self.assertIsNone(lan.find_lan_ip())

    def test_get_lan_ip_falls_back_to_loopback_for_display(self) -> None:
        with mock.patch.object(lan, "candidate_lan_ips", return_value=[]):
            self.assertEqual(lan.get_lan_ip(), lan.LOOPBACK_IP)

    def test_private_address_wins_over_global(self) -> None:
        with mock.patch.object(lan, "socket") as fake:
            fake.socket.side_effect = OSError
            fake.gethostname.return_value = "pc"
            fake.AF_INET = socket.AF_INET
            fake.getaddrinfo.return_value = [
                (None, None, None, "", ("93.184.216.34", 0)),
                (None, None, None, "", ("192.168.1.5", 0)),
            ]
            self.assertEqual(lan.find_lan_ip(), "192.168.1.5")

    def test_loopback_only_host_yields_no_address(self) -> None:
        # hostsファイルの都合で gethostbyname が 127.0.0.1 を返すPCがある。
        with mock.patch.object(lan, "socket") as fake:
            fake.socket.side_effect = OSError
            fake.gethostname.return_value = "pc"
            fake.AF_INET = socket.AF_INET
            fake.getaddrinfo.return_value = [(None, None, None, "", ("127.0.0.1", 0))]
            self.assertIsNone(lan.find_lan_ip())

    def test_unspecified_address_from_getsockname_is_not_used(self) -> None:
        # 経路が無いWindowsで connect() が成功し 0.0.0.0 が返る場合がある。
        with mock.patch.object(lan, "socket") as fake:
            sock = fake.socket.return_value.__enter__.return_value
            sock.getsockname.return_value = ("0.0.0.0", 0)
            fake.gethostname.return_value = "pc"
            fake.AF_INET = socket.AF_INET
            fake.getaddrinfo.return_value = [(None, None, None, "", ("192.168.0.7", 0))]
            self.assertEqual(lan.find_lan_ip(), "192.168.0.7")


if __name__ == "__main__":
    unittest.main()
