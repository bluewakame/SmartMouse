"""QRコードに載せるURLの回帰テスト。

iOSの標準カメラは ``ws://`` を開けず、「使用可能なデータが見つかりません」と
表示して終わる。QRへ載せてよいのは ``http://`` のブラウザ起動用URLだけ。
QRを出す画面が増えたときに、うっかり ``ws://`` を載せないよう固定する。
"""

import ast
import sys
import unittest
from pathlib import Path

RECEIVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RECEIVER_DIR))

from receiver_protocol import build_connection_url, build_page_url

TOKEN = "0123456789abcdef0123456789abcdef"

# QRコードを表示する画面。増えたらここへ足す。
QR_SOURCES = ("receiver_gui.py", "bonjour_main.py")


def qr_payload_attributes(source: Path) -> list[str]:
    """``qr.add_data(self.X)`` の X をすべて拾う。"""
    tree = ast.parse(source.read_text(encoding="utf-8"))
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if getattr(node.func, "attr", "") != "add_data" or not node.args:
            continue
        argument = node.args[0]
        found.append(getattr(argument, "attr", ast.dump(argument)))
    return found


class QRPayloadTests(unittest.TestCase):
    def test_page_url_opens_from_the_standard_camera(self) -> None:
        self.assertTrue(build_page_url("192.168.1.2", 8000, TOKEN).startswith("http://"))

    def test_connection_url_is_not_openable_by_the_camera(self) -> None:
        # ws:// は手入力とiPhoneアプリ専用。QRへ載せてはいけない側。
        self.assertTrue(build_connection_url("192.168.1.2", 8000, TOKEN).startswith("ws://"))

    def test_every_screen_puts_the_page_url_in_the_qr(self) -> None:
        for name in QR_SOURCES:
            with self.subTest(source=name):
                payloads = qr_payload_attributes(RECEIVER_DIR / name)
                self.assertTrue(payloads, f"{name} に qr.add_data が見つからない")
                for payload in payloads:
                    self.assertEqual(
                        payload,
                        "page_url",
                        f"{name} のQRが {payload} を載せている。"
                        "標準カメラで開けるのは page_url だけ。",
                    )


if __name__ == "__main__":
    unittest.main()
