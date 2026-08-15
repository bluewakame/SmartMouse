"""SmartMouse ReceiverとiPhoneアプリで共有する純粋な通信仕様。"""

from __future__ import annotations

import secrets


PROTOCOL_VERSION = "2"
TOKEN_HEX_LENGTH = 32


def create_pairing_token() -> str:
    return secrets.token_hex(TOKEN_HEX_LENGTH // 2)


def is_valid_pairing_token(received: str, expected: str) -> bool:
    return (
        len(received) == TOKEN_HEX_LENGTH
        and len(expected) == TOKEN_HEX_LENGTH
        and secrets.compare_digest(received, expected)
    )


def build_connection_url(ip_address: str, port: int, token: str) -> str:
    if not is_valid_pairing_token(token, token):
        raise ValueError("Invalid pairing token")
    return f"ws://{ip_address}:{port}/ws?token={token}"


def build_service_name(ip_address: str) -> str:
    """iPhoneアプリはBonjourサービス名の末尾から合言葉を取り出すため、形式を固定する。"""
    return f"SmartMouse-{ip_address.replace('.', '-')}"


def build_service_instance(ip_address: str, token: str) -> str:
    if not is_valid_pairing_token(token, token):
        raise ValueError("Invalid pairing token")
    return f"{build_service_name(ip_address)}-{token}"
