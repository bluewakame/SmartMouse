"""スマホから接続できるLANアドレスを選ぶ。

QRコードへ載せるアドレスを決める処理。``0.0.0.0`` や ``127.0.0.1`` を
載せたQRは、読み取れてもスマホからは絶対に繋がらないため、ここで弾く。
pyautogui などに依存させないこと（テストを軽く保つため）。
"""

from __future__ import annotations

import ipaddress
import socket


LOOPBACK_IP = "127.0.0.1"


def is_usable_lan_ip(address: str) -> bool:
    """スマホから接続できる見込みのあるアドレスか。

    QRコードへ載せる前にここで弾く。``0.0.0.0`` や ``127.0.0.1`` を載せた
    QRは、読み取れてもスマホからは絶対に繋がらない。``0.0.0.0`` に至っては
    ホストとして不正なので、iOSのカメラが「使用可能なデータが見つかりません」
    と言って開くことすら拒む。
    """
    try:
        parsed = ipaddress.IPv4Address(address)
    except ValueError:
        return False
    return not (
        parsed.is_unspecified  # 0.0.0.0
        or parsed.is_loopback  # 127.0.0.0/8
        or parsed.is_link_local  # 169.254.0.0/16（DHCPに失敗した状態）
        or parsed.is_multicast
        or parsed.is_reserved
    )


def candidate_lan_ips() -> list[str]:
    """このPCが持つIPv4アドレスを、確からしい順に並べて返す。"""
    candidates: list[str] = []

    def add(address: object) -> None:
        if isinstance(address, str) and address not in candidates:
            candidates.append(address)

    # 既定ルート側のアドレス。複数のNICがあるPCでも、外向きに使う1本が分かる。
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            add(sock.getsockname()[0])
    except OSError:
        # インターネットへの経路が無いLANでは失敗する。それ自体は異常ではない。
        pass

    # ルートが無い場合の総当たり。仮想NICやVPNのアドレスもここに混ざる。
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            add(info[4][0])
    except (OSError, IndexError):
        pass

    usable = [address for address in candidates if is_usable_lan_ip(address)]
    # 家庭やオフィスのLANはプライベートアドレス。グローバルより先に試す。
    usable.sort(key=lambda address: not ipaddress.IPv4Address(address).is_private)
    return usable


def find_lan_ip() -> str | None:
    """スマホから繋げるLANアドレス。見つからなければ None。"""
    candidates = candidate_lan_ips()
    return candidates[0] if candidates else None


def get_lan_ip() -> str:
    """表示用のLANアドレス。見つからない場合もループバックを返して落とさない。

    QRコードを出す側は ``find_lan_ip()`` を使い、None のときは
    「繋がらないQR」を見せずに理由を出すこと。
    """
    return find_lan_ip() or LOOPBACK_IP
