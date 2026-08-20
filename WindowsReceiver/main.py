import ctypes
import json
import socket
import sys
import time
from pathlib import Path
from typing import Any

import pyautogui
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles

import log_filters
from lan import LOOPBACK_IP, candidate_lan_ips, find_lan_ip, get_lan_ip, is_usable_lan_ip
from receiver_protocol import (
    PROTOCOL_VERSION,
    build_connection_url,
    build_page_url,
    create_pairing_token,
    is_valid_pairing_token,
)


# PyInstaller places bundled data under ``sys._MEIPASS``. In the onedir build we
# ship, that is the ``_internal`` folder next to the exe. In a normal Python
# launch the assets continue to live next to this module.
APP_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
# スマホのブラウザ用Webアプリ（SmartMouse-WEB のビルド結果）を置く場所。
WEB_DIR = APP_DIR / "web"
HOST = "0.0.0.0"
PORT = 8000
MAX_MOVE_DELTA = 100
MAX_SCROLL_AMOUNT = 30
MAX_TEXT_LENGTH = 5000
APP_VERSION = "0.5.1"
PAIRING_TOKEN = create_pairing_token()
connected_clients = 0


app = FastAPI(title="SmartMouse Emergency Mouse Keyboard")

# GUI版（receiver_gui.py）もこのモジュールを読み込むため、ここで入れておけば
# どちらの起動経路でもアクセスログから合言葉が消える。
log_filters.install()

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0


@app.get("/health")
async def health() -> dict[str, str]:
    return {
        "status": "ready",
        "version": APP_VERSION,
        # 配布パッケージ名からは分からないので、実行中コードの値をそのまま公開する。
        "protocol": PROTOCOL_VERSION,
        "connected": str(connected_clients > 0).lower(),
    }


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    global connected_clients
    await websocket.accept()
    if not is_valid_pairing_token(
        websocket.query_params.get("token", ""),
        PAIRING_TOKEN,
    ):
        await websocket.close(code=1008, reason="Pairing token required")
        return
    connected_clients += 1

    try:
        await websocket.send_json(
            {"type": "receiver_ready", "version": APP_VERSION, "protocol": PROTOCOL_VERSION}
        )
        print(f"WebSocket connected: {websocket.client}")
        while True:
            message = await websocket.receive_text()
            try:
                data = json.loads(message)
                handle_mouse_message(data)
            except json.JSONDecodeError:
                print(f"Invalid JSON: {message!r}")
            except Exception as exc:
                print(f"Mouse command failed: {exc}")
    except WebSocketDisconnect:
        print(f"WebSocket disconnected: {websocket.client}")
    finally:
        connected_clients = max(0, connected_clients - 1)
        # 通信断の瞬間にドラッグ中でも、Windows側の押下状態を残さない。
        release_all_inputs()


def mount_web_app() -> bool:
    """同梱したWebアプリ（スマホのブラウザ用）を同じポートで配信する。

    ページとWebSocketが同じオリジンになるので、ブラウザの混在コンテンツ制限に
    引っかからず、配信用の別サーバーもポート開放も要らなくなる。
    ``/health``と``/ws``より後ろに載せるため、それらの経路は奪われない。
    """
    if not WEB_DIR.is_dir():
        print(f"Web app not bundled (looked in {WEB_DIR}); serving API only")
        return False
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return True


def handle_mouse_message(data: dict[str, Any]) -> None:
    message_type = data.get("type")

    if message_type == "release_all":
        release_all_inputs()
        return

    if message_type == "move":
        dx = clamp_number(data.get("dx"), -MAX_MOVE_DELTA, MAX_MOVE_DELTA)
        dy = clamp_number(data.get("dy"), -MAX_MOVE_DELTA, MAX_MOVE_DELTA)
        pyautogui.moveRel(dx, dy, duration=0)
        return

    if message_type == "click":
        button = normalize_button(data.get("button"))
        pyautogui.click(button=button)
        return

    if message_type == "double_click":
        pyautogui.doubleClick()
        return

    if message_type == "scroll":
        amount = clamp_number(data.get("amount"), -MAX_SCROLL_AMOUNT, MAX_SCROLL_AMOUNT)
        pyautogui.scroll(amount)
        return

    if message_type == "text":
        text = str(data.get("text", ""))[:MAX_TEXT_LENGTH]
        if text:
            type_text_as_keyboard(text)
        return

    if message_type == "paste_text":
        text = str(data.get("text", ""))[:MAX_TEXT_LENGTH]
        if text:
            print(f"Pasting text: {len(text)} chars")
            paste_text(text)
        return

    if message_type == "paste_enter_text":
        text = str(data.get("text", ""))[:MAX_TEXT_LENGTH]
        if text:
            print(f"Pasting and pressing enter: {len(text)} chars")
            paste_text(text)
            time.sleep(0.08)
            press_virtual_key("enter")
        return

    if message_type == "key":
        key = normalize_key(data.get("key"))
        if key:
            print(f"Pressing key: {key}")
            press_virtual_key(key)
        return

    if message_type == "shortcut":
        shortcut = normalize_shortcut(data.get("shortcut"))
        if shortcut == "copy":
            print("Pressing shortcut: copy")
            pyautogui.hotkey("ctrl", "c")
        elif shortcut == "paste":
            print("Pressing shortcut: paste")
            pyautogui.hotkey("ctrl", "v")
        return

    if message_type == "mouse_down":
        button = normalize_button(data.get("button"))
        pyautogui.mouseDown(button=button)
        return

    if message_type == "mouse_up":
        button = normalize_button(data.get("button"))
        pyautogui.mouseUp(button=button)
        return

    print(f"Unknown message type: {message_type!r}")


def release_all_inputs() -> None:
    for button in ("left", "right", "middle"):
        pyautogui.mouseUp(button=button)
    for key in ("ctrl", "shift", "alt", "win"):
        pyautogui.keyUp(key)


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", ctypes.c_ushort),
        ("wScan", ctypes.c_ushort),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", ctypes.c_long),
        ("dy", ctypes.c_long),
        ("mouseData", ctypes.c_ulong),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", ctypes.c_ulong),
        ("wParamL", ctypes.c_ushort),
        ("wParamH", ctypes.c_ushort),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _fields_ = [("type", ctypes.c_ulong), ("union", INPUT_UNION)]


def type_unicode_text(text: str) -> None:
    user32 = ctypes.windll.user32
    input_keyboard = 1
    keyeventf_keyup = 0x0002
    keyeventf_unicode = 0x0004
    encoded = text.encode("utf-16-le")
    units = [
        int.from_bytes(encoded[index : index + 2], "little")
        for index in range(0, len(encoded), 2)
    ]

    events = []
    for unit in units:
        events.append(
            INPUT(
                type=input_keyboard,
                union=INPUT_UNION(ki=KEYBDINPUT(0, unit, keyeventf_unicode, 0, None)),
            )
        )
        events.append(
            INPUT(
                type=input_keyboard,
                union=INPUT_UNION(ki=KEYBDINPUT(0, unit, keyeventf_unicode | keyeventf_keyup, 0, None)),
            )
        )

    if not events:
        return

    event_array = (INPUT * len(events))(*events)
    user32.SendInput.argtypes = [ctypes.c_uint, ctypes.POINTER(INPUT), ctypes.c_int]
    user32.SendInput.restype = ctypes.c_uint
    sent = user32.SendInput(len(events), event_array, ctypes.sizeof(INPUT))
    if sent != len(events):
        raise OSError(f"SendInput typed {sent}/{len(events)} events")


def paste_text(text: str) -> None:
    set_clipboard_text(text)
    pyautogui.hotkey("ctrl", "v")


def press_virtual_key(key: str) -> None:
    if key == "enter":
        press_scan_key("enter", 0x0D, 0x1C)
        return
    if key == "space":
        press_scan_key("space", 0x20, 0x39)
        return
    if key == "backspace":
        press_scan_key("backspace", 0x08, 0x0E)
        return


def press_scan_key(key: str, virtual_key: int, scan_code: int) -> None:
    # Browser search boxes tend to respond more reliably to physical scan codes
    # than to Unicode characters or VK-only key events.
    user32 = ctypes.windll.user32
    input_keyboard = 1
    keyeventf_keyup = 0x0002
    keyeventf_scancode = 0x0008

    events = [
        INPUT(
            type=input_keyboard,
            union=INPUT_UNION(ki=KEYBDINPUT(0, scan_code, keyeventf_scancode, 0, None)),
        ),
        INPUT(
            type=input_keyboard,
            union=INPUT_UNION(ki=KEYBDINPUT(0, scan_code, keyeventf_scancode | keyeventf_keyup, 0, None)),
        ),
    ]
    event_array = (INPUT * len(events))(*events)
    user32.SendInput.argtypes = [ctypes.c_uint, ctypes.POINTER(INPUT), ctypes.c_int]
    user32.SendInput.restype = ctypes.c_uint
    sent = user32.SendInput(len(events), event_array, ctypes.sizeof(INPUT))
    if sent != len(events):
        raise OSError(f"SendInput {key} scancode sent {sent}/{len(events)} events")

    # Fallback for apps that prefer virtual-key events.
    time.sleep(0.03)
    user32.keybd_event(virtual_key, scan_code, 0, 0)
    time.sleep(0.03)
    user32.keybd_event(virtual_key, scan_code, keyeventf_keyup, 0)


def set_clipboard_text(text: str) -> None:
    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    cf_unicode_text = 13
    gmem_moveable = 0x0002
    encoded = text.encode("utf-16-le") + b"\x00\x00"

    kernel32.GlobalAlloc.argtypes = [ctypes.c_uint, ctypes.c_size_t]
    kernel32.GlobalAlloc.restype = ctypes.c_void_p
    kernel32.GlobalLock.argtypes = [ctypes.c_void_p]
    kernel32.GlobalLock.restype = ctypes.c_void_p
    kernel32.GlobalUnlock.argtypes = [ctypes.c_void_p]
    kernel32.GlobalUnlock.restype = ctypes.c_int
    kernel32.GlobalFree.argtypes = [ctypes.c_void_p]
    kernel32.GlobalFree.restype = ctypes.c_void_p
    user32.OpenClipboard.argtypes = [ctypes.c_void_p]
    user32.OpenClipboard.restype = ctypes.c_int
    user32.EmptyClipboard.restype = ctypes.c_int
    user32.SetClipboardData.argtypes = [ctypes.c_uint, ctypes.c_void_p]
    user32.SetClipboardData.restype = ctypes.c_void_p
    user32.CloseClipboard.restype = ctypes.c_int

    handle = kernel32.GlobalAlloc(gmem_moveable, len(encoded))
    if not handle:
        raise OSError("GlobalAlloc failed")

    try:
        locked = kernel32.GlobalLock(handle)
        if not locked:
            raise OSError("GlobalLock failed")
        ctypes.memmove(locked, encoded, len(encoded))
        kernel32.GlobalUnlock(handle)

        if not user32.OpenClipboard(None):
            raise OSError("OpenClipboard failed")
        try:
            if not user32.EmptyClipboard():
                raise OSError("EmptyClipboard failed")
            if not user32.SetClipboardData(cf_unicode_text, handle):
                raise OSError("SetClipboardData failed")
            handle = None
        finally:
            user32.CloseClipboard()
    finally:
        if handle:
            kernel32.GlobalFree(handle)


def clamp_number(value: Any, minimum: int, maximum: int) -> int:
    try:
        number = int(round(float(value)))
    except (TypeError, ValueError):
        return 0
    return max(minimum, min(maximum, number))


def normalize_button(value: Any) -> str:
    return "right" if value == "right" else "left"


def normalize_key(value: Any) -> str | None:
    allowed_keys = {"enter", "space", "backspace"}
    key = str(value).lower()
    return key if key in allowed_keys else None


def normalize_shortcut(value: Any) -> str | None:
    allowed_shortcuts = {"copy", "paste"}
    shortcut = str(value).lower()
    return shortcut if shortcut in allowed_shortcuts else None


KANA_ROMAJI = {
    "あ": "a",
    "い": "i",
    "う": "u",
    "え": "e",
    "お": "o",
    "ぁ": "xa",
    "ぃ": "xi",
    "ぅ": "xu",
    "ぇ": "xe",
    "ぉ": "xo",
    "か": "ka",
    "き": "ki",
    "く": "ku",
    "け": "ke",
    "こ": "ko",
    "が": "ga",
    "ぎ": "gi",
    "ぐ": "gu",
    "げ": "ge",
    "ご": "go",
    "さ": "sa",
    "し": "shi",
    "す": "su",
    "せ": "se",
    "そ": "so",
    "ざ": "za",
    "じ": "ji",
    "ず": "zu",
    "ぜ": "ze",
    "ぞ": "zo",
    "た": "ta",
    "ち": "chi",
    "つ": "tsu",
    "て": "te",
    "と": "to",
    "だ": "da",
    "ぢ": "di",
    "づ": "du",
    "で": "de",
    "ど": "do",
    "っ": "",
    "な": "na",
    "に": "ni",
    "ぬ": "nu",
    "ね": "ne",
    "の": "no",
    "は": "ha",
    "ひ": "hi",
    "ふ": "fu",
    "へ": "he",
    "ほ": "ho",
    "ば": "ba",
    "び": "bi",
    "ぶ": "bu",
    "べ": "be",
    "ぼ": "bo",
    "ぱ": "pa",
    "ぴ": "pi",
    "ぷ": "pu",
    "ぺ": "pe",
    "ぽ": "po",
    "ま": "ma",
    "み": "mi",
    "む": "mu",
    "め": "me",
    "も": "mo",
    "や": "ya",
    "ゆ": "yu",
    "よ": "yo",
    "ゃ": "xya",
    "ゅ": "xyu",
    "ょ": "xyo",
    "ら": "ra",
    "り": "ri",
    "る": "ru",
    "れ": "re",
    "ろ": "ro",
    "わ": "wa",
    "を": "wo",
    "ん": "n",
    "ゔ": "vu",
    "ー": "-",
    "。": ".",
    "、": ",",
    "・": "/",
    "「": "[",
    "」": "]",
    "！": "!",
    "？": "?",
    "　": " ",
}

DIGRAPH_ROMAJI = {
    "きゃ": "kya",
    "きゅ": "kyu",
    "きょ": "kyo",
    "ぎゃ": "gya",
    "ぎゅ": "gyu",
    "ぎょ": "gyo",
    "しゃ": "sha",
    "しゅ": "shu",
    "しょ": "sho",
    "じゃ": "ja",
    "じゅ": "ju",
    "じょ": "jo",
    "ちゃ": "cha",
    "ちゅ": "chu",
    "ちょ": "cho",
    "ぢゃ": "dya",
    "ぢゅ": "dyu",
    "ぢょ": "dyo",
    "にゃ": "nya",
    "にゅ": "nyu",
    "にょ": "nyo",
    "ひゃ": "hya",
    "ひゅ": "hyu",
    "ひょ": "hyo",
    "びゃ": "bya",
    "びゅ": "byu",
    "びょ": "byo",
    "ぴゃ": "pya",
    "ぴゅ": "pyu",
    "ぴょ": "pyo",
    "みゃ": "mya",
    "みゅ": "myu",
    "みょ": "myo",
    "りゃ": "rya",
    "りゅ": "ryu",
    "りょ": "ryo",
    "ふぁ": "fa",
    "ふぃ": "fi",
    "ふぇ": "fe",
    "ふぉ": "fo",
    "てぃ": "thi",
    "でぃ": "dhi",
    "うぃ": "wi",
    "うぇ": "we",
    "うぉ": "who",
    "ゔぁ": "va",
    "ゔぃ": "vi",
    "ゔぇ": "ve",
    "ゔぉ": "vo",
}


def type_text_as_keyboard(text: str) -> None:
    romaji, skipped = text_to_romaji(text)
    if not romaji:
        print("Typing text skipped: no romaji-compatible characters")
        return

    print(f"Typing romaji: {romaji!r}")
    if skipped:
        print(f"Skipped non-kana characters: {skipped!r}")
    pyautogui.write(romaji, interval=0.001)


def text_to_romaji(text: str) -> tuple[str, str]:
    normalized = "".join(katakana_to_hiragana(char) for char in text)
    output: list[str] = []
    skipped: list[str] = []
    index = 0

    while index < len(normalized):
        char = normalized[index]

        if char == "っ":
            next_romaji = lookup_romaji(normalized, index + 1)
            if next_romaji and next_romaji[0].isalpha():
                output.append(next_romaji[0])
            index += 1
            continue

        if char == "ん":
            next_romaji = lookup_romaji(normalized, index + 1)
            if next_romaji and next_romaji[0] in "aiueoy":
                output.append("nn")
            else:
                output.append("n")
            index += 1
            continue

        pair = normalized[index : index + 2]
        if pair in DIGRAPH_ROMAJI:
            output.append(DIGRAPH_ROMAJI[pair])
            index += 2
            continue

        if char in KANA_ROMAJI:
            output.append(KANA_ROMAJI[char])
        elif char.isascii():
            output.append(char)
        elif char in {"￥", "¥"}:
            output.append("\\")
        else:
            skipped.append(char)
        index += 1

    return "".join(output), "".join(skipped)


def lookup_romaji(text: str, index: int) -> str:
    if index >= len(text):
        return ""
    pair = text[index : index + 2]
    if pair in DIGRAPH_ROMAJI:
        return DIGRAPH_ROMAJI[pair]
    return KANA_ROMAJI.get(text[index], text[index] if text[index].isascii() else "")


def katakana_to_hiragana(char: str) -> str:
    code = ord(char)
    if 0x30A1 <= code <= 0x30F6:
        return chr(code - 0x60)
    return char


def print_startup_banner() -> None:
    ip_address = get_lan_ip()
    print()
    print("=" * 48)
    print("SmartMouse Emergency Mouse Keyboard")
    print(f"Receiver v{APP_VERSION} (protocol {PROTOCOL_VERSION}) started")
    print()
    print("Open this address in your phone's browser:")
    print(build_page_url(ip_address, PORT, PAIRING_TOKEN))
    print()
    print("Pair the iPhone app with this address:")
    print(build_connection_url(ip_address, PORT, PAIRING_TOKEN))
    print()
    print("Keep your iPhone and PC on the same Wi-Fi/LAN.")
    print("Press Ctrl+C to stop.")
    print("=" * 48)
    print()


mount_web_app()


if __name__ == "__main__":
    print_startup_banner()
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
