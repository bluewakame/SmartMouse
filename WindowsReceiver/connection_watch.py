"""スマホが接続したことを、PCの持ち主へ知らせるかどうかの判断。

このReceiverは、他人のPCで起動されると「画面の見えない範囲でマウスと
キーボードを操作される」状態を作れてしまう。起動にはPCへの物理的な操作が
必要なので、それができる相手はもっと危険なこともできる——とはいえ、
こっそり動かし続けられるのは避けたい。

接続を承認制にすると「マウスが壊れて操作できない」という本来の用途を
壊してしまう。そこで、防ぐのではなく**隠れられなくする**方針を取る。
接続のたびに通知を出せば、席へ戻った持ち主が気付ける。

Wi-Fiが不安定な環境ではクライアントが自動再接続を繰り返すため、
そのたびに通知すると邪魔になる。短い間隔での連続通知は抑える。

tkinter や pystray に依存させないこと（テストを軽く保つため）。
"""

from __future__ import annotations


# 再接続の揺れで通知が連発しないよう、この秒数は次を出さない。
DEFAULT_QUIET_SECONDS = 60.0


class ConnectionWatcher:
    """接続数の変化を見て、通知すべき瞬間を教える。"""

    def __init__(self, quiet_seconds: float = DEFAULT_QUIET_SECONDS) -> None:
        self.quiet_seconds = quiet_seconds
        self._connected = False
        self._last_notified_at: float | None = None

    @property
    def connected(self) -> bool:
        return self._connected

    def update(self, connected: bool, now: float) -> bool:
        """現在の接続状態を渡すと、通知すべきなら True を返す。

        通知するのは「繋がっていない状態から繋がった瞬間」だけ。
        繋がったままの間や、切れた瞬間には出さない。
        """
        was_connected = self._connected
        self._connected = connected

        if not connected or was_connected:
            return False

        if self._last_notified_at is not None:
            if now - self._last_notified_at < self.quiet_seconds:
                return False

        self._last_notified_at = now
        return True
