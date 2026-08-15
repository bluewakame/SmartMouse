import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from receiver_protocol import (
    PROTOCOL_VERSION,
    TOKEN_HEX_LENGTH,
    build_connection_url,
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


if __name__ == "__main__":
    unittest.main()
