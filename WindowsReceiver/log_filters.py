"""ログに合言葉を残さないためのフィルター。

Uvicornのアクセスログはリクエスト行をクエリ文字列ごと出力するため、
``/ws?token=…`` への接続が来るたびに合言葉が平文でログに残る。ログは
コンソール画面・不具合報告のスクリーンショット・画面共有を通じて外へ出る
経路があり、合言葉を得た相手はPCのマウスとキーボードを自由に操作できる。

起動時バナーのURL表示は、利用者が読み取るために意図して出しているものなので
ここでは触らない。伏せるのは、出す必要のないアクセスログのほうだけ。
"""

from __future__ import annotations

import logging
import re


REDACTED = "<redacted>"

# 合言葉は16進数だが、桁数の違う値や別形式が来ても伏せ損ねないよう緩めに拾う。
_TOKEN_PATTERN = re.compile(r"(token=)[^&\s\"']+")


def redact(text: str) -> str:
    """``token=…`` の値を伏せた文字列を返す。"""
    return _TOKEN_PATTERN.sub(rf"\1{REDACTED}", text)


class PairingTokenFilter(logging.Filter):
    """ログレコードの本文と引数から合言葉を取り除く。

    Uvicornはリクエスト行を``record.args``へ渡す実装だが、版によって
    組み立て方が変わりうる。内部構造に依存しないよう、``msg``と``args``の
    文字列を両方とも通す。
    """

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = redact(record.msg)
        if isinstance(record.args, tuple):
            record.args = tuple(
                redact(value) if isinstance(value, str) else value for value in record.args
            )
        elif isinstance(record.args, dict):
            record.args = {
                key: redact(value) if isinstance(value, str) else value
                for key, value in record.args.items()
            }
        return True


def install() -> None:
    """Uvicornのロガーへフィルターを取り付ける。

    ロガーに付けたフィルターは子ロガーから伝播してきたレコードには効かないため、
    実際に出力しているロガーそれぞれへ直接付ける。二重登録は避ける。
    """
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(name)
        if not any(isinstance(existing, PairingTokenFilter) for existing in logger.filters):
            logger.addFilter(PairingTokenFilter())
