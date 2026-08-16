import logging
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from log_filters import REDACTED, PairingTokenFilter, install, redact


TOKEN = "0123456789abcdef0123456789abcdef"


def make_record(msg: str, args: object) -> logging.LogRecord:
    return logging.LogRecord("uvicorn.access", logging.INFO, __file__, 1, msg, args, None)


class RedactTests(unittest.TestCase):
    def test_query_token_is_replaced(self) -> None:
        self.assertEqual(redact(f"/ws?token={TOKEN}"), f"/ws?token={REDACTED}")

    def test_token_before_another_parameter_is_replaced(self) -> None:
        self.assertEqual(redact(f"/?token={TOKEN}&x=1"), f"/?token={REDACTED}&x=1")

    def test_text_without_token_is_untouched(self) -> None:
        self.assertEqual(redact("/health"), "/health")

    def test_every_occurrence_is_replaced(self) -> None:
        self.assertNotIn(TOKEN, redact(f"a token={TOKEN} b token={TOKEN}"))


class PairingTokenFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.filter = PairingTokenFilter()

    def test_uvicorn_access_record_is_redacted(self) -> None:
        # Uvicornはリクエスト行を args へ渡し、パスにクエリ文字列を含める。
        record = make_record(
            '%s - "%s %s HTTP/%s" %d',
            ("127.0.0.1:52000", "GET", f"/?token={TOKEN}", "1.1", 200),
        )
        self.filter.filter(record)
        self.assertNotIn(TOKEN, record.getMessage())
        self.assertIn(REDACTED, record.getMessage())

    def test_token_in_message_itself_is_redacted(self) -> None:
        record = make_record(f"connect ws://127.0.0.1:8000/ws?token={TOKEN}", None)
        self.filter.filter(record)
        self.assertNotIn(TOKEN, record.getMessage())

    def test_non_string_args_survive(self) -> None:
        record = make_record("%s %d", ("/health", 200))
        self.filter.filter(record)
        self.assertEqual(record.getMessage(), "/health 200")

    def test_filter_keeps_the_record(self) -> None:
        record = make_record("/health", None)
        self.assertTrue(self.filter.filter(record))


class InstallTests(unittest.TestCase):
    def test_install_is_idempotent(self) -> None:
        logger = logging.getLogger("uvicorn.access")
        install()
        install()
        attached = [f for f in logger.filters if isinstance(f, PairingTokenFilter)]
        self.assertEqual(len(attached), 1)


if __name__ == "__main__":
    unittest.main()
