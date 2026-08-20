"""SmartMouse ReceiverのWindows GUI／タスクトレイ版エントリーポイント。"""

from __future__ import annotations

import logging
import os
import socket
import sys
import threading
import time
import tkinter as tk
import zipfile
from pathlib import Path
from tkinter import filedialog, messagebox

import pystray
import qrcode
import uvicorn
from PIL import Image, ImageTk
from zeroconf import IPVersion, ServiceInfo, Zeroconf

# タスクトレイとexeのアイコンを同じ絵から作るため、描画はapp_iconへ寄せてある。
from app_icon import ACCENT, BACKGROUND, CONNECTED, build_icon_image
from connection_watch import ConnectionWatcher
from main import APP_VERSION, HOST, PAIRING_TOKEN, PORT, PROTOCOL_VERSION, app, find_lan_ip, get_lan_ip
import main as receiver
from receiver_protocol import build_connection_url, build_page_url, build_service_instance


APP_NAME = "SmartMouse Receiver"
PANEL = "#1C2023"
TEXT = "#F6F7F8"
SECONDARY = "#9DA3A8"
WARNING = "#FFD699"


def app_data_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    path = Path(base) / "SmartMouse"
    path.mkdir(parents=True, exist_ok=True)
    return path


LOG_PATH = app_data_dir() / "receiver.log"
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    encoding="utf-8",
    force=True,
)
logger = logging.getLogger(APP_NAME)


def tray_image(connected: bool = False) -> Image.Image:
    return build_icon_image(64, CONNECTED if connected else ACCENT)


class ReceiverServer:
    def __init__(self) -> None:
        self.server: uvicorn.Server | None = None
        self.zeroconf: Zeroconf | None = None
        self.service_info: ServiceInfo | None = None
        self.error = ""
        self.running = False
        self.stopping = False

    def start(self) -> None:
        threading.Thread(target=self._run, name="SmartMouseServer", daemon=True).start()

    def _run(self) -> None:
        ip_address = get_lan_ip()
        encoded_ip = ip_address.replace(".", "-")
        service_type = "_smartmouse._tcp.local."
        self.service_info = ServiceInfo(
            service_type,
            f"{build_service_instance(ip_address, PAIRING_TOKEN)}.{service_type}",
            addresses=[socket.inet_aton(ip_address)],
            port=PORT,
            properties={
                "path": "/ws",
                "version": APP_VERSION,
                "token": PAIRING_TOKEN,
                "protocol": PROTOCOL_VERSION,
            },
            server=f"smartmouse-{encoded_ip}.local.",
        )

        try:
            self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            self.zeroconf.register_service(self.service_info)
        except Exception as exc:
            logger.warning("Bonjour registration failed: %s", exc)

        try:
            for attempt in range(1, 4):
                config = uvicorn.Config(
                    app,
                    host=HOST,
                    port=PORT,
                    log_level="info",
                    log_config=None,
                )
                self.server = uvicorn.Server(config)
                self.running = True
                logger.info(
                    "Receiver v%s started at ws://%s:%s/ws (attempt %s)",
                    APP_VERSION, ip_address, PORT, attempt,
                )
                self.server.run()
                self.running = False
                if self.stopping:
                    break
                logger.warning("Receiver stopped unexpectedly; restarting")
                time.sleep(2)
            if not self.stopping:
                self.error = "自動復旧できませんでした。8000番ポートを確認してください。"
        except Exception as exc:
            self.error = str(exc)
            logger.exception("Receiver failed")
        finally:
            self.running = False
            if self.zeroconf:
                try:
                    if self.service_info:
                        self.zeroconf.unregister_service(self.service_info)
                    self.zeroconf.close()
                except Exception:
                    logger.exception("Bonjour cleanup failed")

    def stop(self) -> None:
        self.stopping = True
        if self.server:
            self.server.should_exit = True


class ReceiverWindow:
    def __init__(self) -> None:
        self.server = ReceiverServer()
        self.root = tk.Tk()
        self.root.title(APP_NAME)
        self.root.geometry("480x680")
        self.root.minsize(420, 620)
        self.root.configure(bg=BACKGROUND)
        self.root.protocol("WM_DELETE_WINDOW", self.hide_to_tray)
        self.start_minimized = "--minimized" in sys.argv

        # LANアドレスが見つからないまま 0.0.0.0 や 127.0.0.1 でQRを作ると、
        # 読み取れてもスマホからは絶対に繋がらない。作らずに理由を出す。
        lan_ip = find_lan_ip()
        self.lan_ip = lan_ip
        # QRコードにはブラウザ用のhttp URLを載せる。標準のカメラアプリで開けるうえ、
        # iPhoneアプリもこの形式を ws:// に読み替えられるので、QRは1つで足りる。
        self.page_url = build_page_url(lan_ip, PORT, PAIRING_TOKEN) if lan_ip else ""
        self.connection_url = build_connection_url(lan_ip, PORT, PAIRING_TOKEN) if lan_ip else ""
        self.qr_photo: ImageTk.PhotoImage | None = None
        self.status_text = tk.StringVar(value="受信機を起動しています…")
        self.status_color = SECONDARY
        # 他人のPCで黙って動かされないよう、接続を検出して知らせる。
        self.connection = ConnectionWatcher()
        self.startup_enabled = tk.BooleanVar(value=self.is_startup_enabled())
        self.tray = self.make_tray()

        self.build_ui()
        self.server.start()
        threading.Thread(target=self.tray.run, name="SmartMouseTray", daemon=True).start()
        self.poll_status()
        if self.start_minimized:
            self.root.after(50, self.root.withdraw)

    def build_ui(self) -> None:
        content = tk.Frame(self.root, bg=BACKGROUND, padx=28, pady=22)
        content.pack(fill="both", expand=True)

        tk.Label(
            content, text="SmartMouse Receiver", bg=BACKGROUND, fg=TEXT,
            font=("Segoe UI", 24, "bold"),
        ).pack(anchor="w")
        tk.Label(
            content, text="スマホをWindowsのマウス・キーボードに",
            bg=BACKGROUND, fg=SECONDARY, font=("Yu Gothic UI", 10),
        ).pack(anchor="w", pady=(2, 18))

        status_panel = tk.Frame(content, bg=PANEL, padx=14, pady=11)
        status_panel.pack(fill="x")
        self.status_dot = tk.Label(
            status_panel, text="●", bg=PANEL, fg=SECONDARY,
            font=("Segoe UI", 13, "bold"),
        )
        self.status_dot.pack(side="left")
        tk.Label(
            status_panel, textvariable=self.status_text, bg=PANEL, fg=TEXT,
            font=("Yu Gothic UI", 11, "bold"),
        ).pack(side="left", padx=(8, 0))

        qr_panel = tk.Frame(content, bg=PANEL, padx=18, pady=18)
        qr_panel.pack(fill="both", expand=True, pady=14)
        tk.Label(
            qr_panel, text="スマホのカメラで読み取ってください",
            bg=PANEL, fg=TEXT, font=("Yu Gothic UI", 13, "bold"),
        ).pack(pady=(0, 2))
        tk.Label(
            qr_panel, text="ブラウザが開いてそのまま操作できます（アプリでも読めます）",
            bg=PANEL, fg=SECONDARY, font=("Yu Gothic UI", 9),
        ).pack(pady=(0, 12))

        if self.page_url:
            self.build_qr_panel(qr_panel)
        else:
            self.build_no_network_panel(qr_panel)

        tk.Label(
            content,
            text="スマホとこのPCを同じWi‑Fiにつないでください。",
            bg=BACKGROUND, fg=SECONDARY, font=("Yu Gothic UI", 10),
        ).pack()

        startup = tk.Checkbutton(
            content,
            text="Windowsへのサインイン時に自動で起動",
            variable=self.startup_enabled,
            command=self.toggle_startup,
            bg=BACKGROUND,
            fg=TEXT,
            activebackground=BACKGROUND,
            activeforeground=TEXT,
            selectcolor=PANEL,
            font=("Yu Gothic UI", 10),
        )
        startup.pack(anchor="w", pady=(14, 8))

        buttons = tk.Frame(content, bg=BACKGROUND)
        buttons.pack(fill="x")
        tk.Button(
            buttons, text="タスクトレイにしまう", command=self.hide_to_tray,
            bg=ACCENT, fg="#07110D", activebackground="#28BD87",
            relief="flat", font=("Yu Gothic UI", 10, "bold"), padx=14, pady=9,
        ).pack(side="left", fill="x", expand=True)
        tk.Button(
            buttons, text="終了", command=self.confirm_exit,
            bg=PANEL, fg=TEXT, activebackground="#292E31",
            relief="flat", font=("Yu Gothic UI", 10, "bold"), padx=14, pady=9,
        ).pack(side="left", padx=(8, 0))
        diagnostic_buttons = tk.Frame(content, bg=BACKGROUND)
        diagnostic_buttons.pack(fill="x", pady=(6, 0))
        tk.Button(
            diagnostic_buttons, text="問題の記録を開く", command=self.open_log,
            bg=BACKGROUND, fg=SECONDARY, activebackground=BACKGROUND,
            activeforeground=TEXT, relief="flat", font=("Yu Gothic UI", 9),
        ).pack(side="right")
        tk.Button(
            diagnostic_buttons, text="診断情報を保存", command=self.save_diagnostics,
            bg=BACKGROUND, fg=SECONDARY, activebackground=BACKGROUND,
            activeforeground=TEXT, relief="flat", font=("Yu Gothic UI", 9),
        ).pack(side="left")

    def build_qr_panel(self, qr_panel: tk.Frame) -> None:
        qr = qrcode.QRCode(border=2, box_size=9)
        qr.add_data(self.page_url)
        qr.make(fit=True)
        qr_image = qr.make_image(fill_color="#111416", back_color="#FFFFFF").convert("RGB")
        qr_image.thumbnail((290, 290), Image.Resampling.LANCZOS)
        self.qr_photo = ImageTk.PhotoImage(qr_image)
        tk.Label(qr_panel, image=self.qr_photo, bg=PANEL).pack()
        tk.Label(
            qr_panel, text=self.page_url, bg=PANEL, fg=SECONDARY,
            font=("Consolas", 9),
        ).pack(pady=(10, 0))
        # QRが読めない端末のために、手入力用のアドレスも出しておく。
        tk.Label(
            qr_panel, text=f"手入力用: {self.connection_url}", bg=PANEL, fg=SECONDARY,
            font=("Consolas", 8),
        ).pack(pady=(4, 0))

    def build_no_network_panel(self, qr_panel: tk.Frame) -> None:
        """LANアドレスが無いときの表示。

        繋がらないQRを出すより、理由を出したほうが早く解決できる。
        """
        tk.Label(
            qr_panel, text="このPCのLANアドレスが見つかりません",
            bg=PANEL, fg=WARNING, font=("Yu Gothic UI", 12, "bold"),
        ).pack(pady=(8, 6))
        tk.Label(
            qr_panel,
            text=(
                "Wi‑Fiまたは有線LANに繋がっていないため、\n"
                "スマホから接続できるアドレスを作れません。\n\n"
                "・Wi‑Fiに接続してから、この画面を開き直してください\n"
                "・VPNを使っている場合は、一度切ってお試しください"
            ),
            bg=PANEL, fg=SECONDARY, font=("Yu Gothic UI", 10), justify="left",
        ).pack(pady=(0, 8))

    def make_tray(self) -> pystray.Icon:
        menu = pystray.Menu(
            pystray.MenuItem("QRコードを表示", self.show_from_tray, default=True),
            pystray.MenuItem("終了", self.exit_from_tray),
        )
        return pystray.Icon("SmartMouseReceiver", tray_image(), APP_NAME, menu)

    def poll_status(self) -> None:
        connected = receiver.connected_clients > 0

        if self.server.error:
            self.status_text.set("起動できませんでした")
            self.status_dot.configure(fg="#FF5C5C")
        elif connected:
            self.status_text.set("スマホと接続中（操作されています）")
            self.status_dot.configure(fg=CONNECTED)
        elif self.server.running:
            self.status_text.set("接続待機中")
            self.status_dot.configure(fg="#F0B84B")
        else:
            self.status_text.set("受信機を起動しています…")
            self.status_dot.configure(fg=SECONDARY)

        was_connected = self.connection.connected
        if self.connection.update(connected, time.monotonic()):
            self.announce_connection()
        if connected != was_connected:
            self.refresh_tray_icon(connected)

        self.root.after(500, self.poll_status)

    def announce_connection(self) -> None:
        """スマホが繋がったことをWindowsの通知で知らせる。

        ウィンドウを閉じてトレイに入れていると、画面内の状態表示は見えない。
        通知なら履歴に残るので、席を外していた持ち主があとから気付ける。
        """
        try:
            self.tray.notify(
                "スマートフォンがこのPCの操作を開始しました。\n"
                "心当たりが無い場合は、タスクトレイのSmartMouseアイコンを"
                "右クリックして「終了」を選んでください。",
                APP_NAME,
            )
        except Exception:
            # 通知はOSや環境によっては出せない。出せなくても動作は続ける。
            pass

    def refresh_tray_icon(self, connected: bool) -> None:
        """接続中はトレイアイコンの色を変える。"""
        try:
            self.tray.icon = tray_image(connected)
        except Exception:
            pass

    def hide_to_tray(self) -> None:
        self.root.withdraw()
        try:
            self.tray.notify(
                "SmartMouse Receiverはバックグラウンドで動作しています。",
                APP_NAME,
            )
        except Exception:
            pass

    def show_from_tray(self, _icon=None, _item=None) -> None:
        self.root.after(0, self.show_window)

    def show_window(self) -> None:
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def exit_from_tray(self, _icon=None, _item=None) -> None:
        self.root.after(0, self.exit_app)

    def confirm_exit(self) -> None:
        if messagebox.askyesno(
            APP_NAME,
            "Receiverを終了すると、iPhoneから操作できなくなります。終了しますか？",
            parent=self.root,
        ):
            self.exit_app()

    def exit_app(self) -> None:
        self.server.stop()
        try:
            self.tray.stop()
        finally:
            self.root.destroy()

    def open_log(self) -> None:
        try:
            if sys.platform == "win32":
                os.startfile(LOG_PATH)  # type: ignore[attr-defined]
        except Exception as exc:
            messagebox.showerror(
                APP_NAME,
                f"問題の記録を開けませんでした。\n\n{LOG_PATH}\n\n{exc}",
                parent=self.root,
            )

    def save_diagnostics(self) -> None:
        destination = filedialog.asksaveasfilename(
            parent=self.root,
            title="診断情報を保存",
            initialfile="SmartMouse-Diagnostics.zip",
            defaultextension=".zip",
            filetypes=[("ZIPファイル", "*.zip")],
        )
        if not destination:
            return
        try:
            info = (
                f"SmartMouse Receiver v{APP_VERSION}\n"
                f"Protocol: {PROTOCOL_VERSION}\n"
                f"Connected clients: {receiver.connected_clients}\n"
                f"Address: {get_lan_ip()}:{PORT}\n"
            )
            info_path = app_data_dir() / "diagnostics.txt"
            info_path.write_text(info, encoding="utf-8")
            with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
                if LOG_PATH.exists():
                    archive.write(LOG_PATH, "receiver.log")
                archive.write(info_path, "diagnostics.txt")
            messagebox.showinfo(APP_NAME, "診断情報を保存しました。", parent=self.root)
        except Exception as exc:
            logger.exception("Diagnostics export failed")
            messagebox.showerror(
                APP_NAME,
                f"診断情報を保存できませんでした。\n\n{exc}",
                parent=self.root,
            )

    def toggle_startup(self) -> None:
        try:
            self.set_startup_enabled(self.startup_enabled.get())
        except Exception as exc:
            logger.exception("Startup setting failed")
            self.startup_enabled.set(not self.startup_enabled.get())
            messagebox.showerror(
                APP_NAME,
                f"自動起動の設定を変更できませんでした。\n\n{exc}",
                parent=self.root,
            )

    @staticmethod
    def startup_command() -> str:
        if getattr(sys, "frozen", False):
            return f'"{sys.executable}" --minimized'
        script = Path(__file__).resolve()
        return f'"{sys.executable}" "{script}" --minimized'

    @staticmethod
    def is_startup_enabled() -> bool:
        if sys.platform != "win32":
            return False
        import winreg

        try:
            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Run",
            ) as key:
                winreg.QueryValueEx(key, APP_NAME)
            return True
        except OSError:
            return False

    @classmethod
    def set_startup_enabled(cls, enabled: bool) -> None:
        if sys.platform != "win32":
            return
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            if enabled:
                winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, cls.startup_command())
            else:
                try:
                    winreg.DeleteValue(key, APP_NAME)
                except FileNotFoundError:
                    pass

    def run(self) -> None:
        self.root.mainloop()


_single_instance_handle = None


def acquire_single_instance() -> bool:
    global _single_instance_handle
    if sys.platform != "win32":
        return True
    import ctypes

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    _single_instance_handle = kernel32.CreateMutexW(None, False, "Local\\SmartMouseReceiver")
    return kernel32.GetLastError() != 183


if __name__ == "__main__":
    try:
        if acquire_single_instance():
            ReceiverWindow().run()
        else:
            temporary_root = tk.Tk()
            temporary_root.withdraw()
            messagebox.showinfo(
                APP_NAME,
                "SmartMouse Receiverはすでに動作しています。\n"
                "画面右下のタスクトレイから開いてください。",
                parent=temporary_root,
            )
            temporary_root.destroy()
    except Exception:
        logger.exception("Uncaught GUI error")
        raise
