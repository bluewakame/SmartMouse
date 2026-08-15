import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receiver_protocol import (
    PROTOCOL_VERSION,
    TOKEN_HEX_LENGTH,
    build_connection_url,
    build_service_instance,
    create_pairing_token,
    is_valid_pairing_token,
)


class ReceiverProtocolTests(unittest.TestCase):
    def test_pairing_token_is_random_hex(self) -> None:
        first = create_pairing_token()
        second = create_pairing_token()
        self.assertEqual(len(first), TOKEN_HEX_LENGTH)
        self.assertNotEqual(first, second)
        int(first, 16)

    def test_token_validation_rejects_wrong_or_short_value(self) -> None:
        expected = "a" * TOKEN_HEX_LENGTH
        self.assertTrue(is_valid_pairing_token(expected, expected))
        self.assertFalse(is_valid_pairing_token("b" * TOKEN_HEX_LENGTH, expected))
        self.assertFalse(is_valid_pairing_token("a", expected))

    def test_connection_url_contains_protocol_path_and_token(self) -> None:
        token = "c" * TOKEN_HEX_LENGTH
        self.assertEqual(
            build_connection_url("192.168.1.10", 8000, token),
            f"ws://192.168.1.10:8000/ws?token={token}",
        )
        self.assertEqual(PROTOCOL_VERSION, "2")

    def test_service_instance_matches_iphone_parser(self) -> None:
        # ReceiverDiscovery.swiftは"SmartMouse-"を外し、"-"区切りの5要素以上、
        # 末尾がTOKEN_HEX_LENGTH桁であることを条件に接続先を組み立てる。
        token = "d" * TOKEN_HEX_LENGTH
        name = build_service_instance("192.168.1.10", token)

        self.assertTrue(name.startswith("SmartMouse-"))
        pieces = name[len("SmartMouse-"):].split("-")
        self.assertGreaterEqual(len(pieces), 5)
        self.assertEqual(pieces[-1], token)
        self.assertEqual(len(pieces[-1]), TOKEN_HEX_LENGTH)
        self.assertEqual(".".join(pieces[:-1]), "192.168.1.10")
        # Bonjourのサービス名は63バイトまで。
        self.assertLessEqual(len(name.encode("utf-8")), 63)

    def test_service_instance_rejects_missing_token(self) -> None:
        with self.assertRaises(ValueError):
            build_service_instance("192.168.1.10", "")


if __name__ == "__main__":
    unittest.main()
