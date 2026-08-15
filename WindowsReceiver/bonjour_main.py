"""SmartMouse Receiverをタスクトレイ常駐アプリとして起動します。"""

import socket
import os
import sys
import threading
import tkinter as tk
import webbrowser

import pystray
import qrcode
import uvicorn
from PIL import Image, ImageDraw, ImageTk
from zeroconf import IPVersion, ServiceInfo, Zeroconf

from main import HOST, PAIRING_TOKEN, PORT, app, get_lan_ip
from receiver_protocol import build_service_instance


if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")


class SmartMouseTrayApp:
    def __init__(self) -> None:
        self.ip_address = get_lan_ip()
        self.web_url = f"http://{self.ip_address}:{PORT}/?token={PAIRING_TOKEN}"
        self.connection_url = f"ws://{self.ip_address}:{PORT}/ws?token={PAIRING_TOKEN}"
        self.service_info = self.create_service_info()
        self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self.server = uvicorn.Server(
            uvicorn.Config(
                app,
                host=HOST,
                port=PORT,
                log_level="warning",
                log_config=None,
                access_log=False,
            )
        )
        self.server_thread = threading.Thread(target=self.run_server, daemon=True)
        self.service_registered = False
        self.server_started = False
        self.root = tk.Tk()
        self.root.title("SmartMouse Receiver")
        self.root.resizable(False, False)
        self.root.protocol("WM_DELETE_WINDOW", self.hide_window)
        self.qr_photo: ImageTk.PhotoImage | None = None
        self.status_var = tk.StringVar(value="SmartMouse Receiver is running.")
        self.tray_icon = pystray.Icon(
            "SmartMouseReceiver",
            self.create_tray_image(),
            "SmartMouse Receiver",
            pystray.Menu(
                pystray.MenuItem("Show QR Code", self.show_window_from_tray),
                pystray.MenuItem("Open Web UI", self.open_web_ui_from_tray),
                pystray.MenuItem("Copy Connection URL", self.copy_url_from_tray),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Exit", self.quit_from_tray),
            ),
        )
        self.build_window()

    def create_service_info(self) -> ServiceInfo:
        encoded_ip = self.ip_address.replace(".", "-")
        service_type = "_smartmouse._tcp.local."
        return ServiceInfo(
            service_type,
            f"{build_service_instance(self.ip_address, PAIRING_TOKEN)}.{service_type}",
            addresses=[socket.inet_aton(self.ip_address)],
            port=PORT,
            properties={"path": "/ws", "token": PAIRING_TOKEN},
            server=f"smartmouse-{encoded_ip}.local.",
        )

    def create_tray_image(self) -> Image.Image:
        image = Image.new("RGBA", (64, 64), (24, 34, 44, 255))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((8, 8, 56, 56), radius=12, fill=(48, 130, 206, 255))
        draw.ellipse((20, 14, 44, 38), fill=(245, 248, 252, 255))
        draw.rounded_rectangle((28, 34, 36, 54), radius=4, fill=(245, 248, 252, 255))
        return image

    def build_window(self) -> None:
        frame = tk.Frame(self.root, padx=18, pady=16, bg="#f7f9fb")
        frame.pack(fill="both", expand=True)

        tk.Label(
            frame,
            text="SmartMouse Receiver",
            font=("Segoe UI", 16, "bold"),
            bg="#f7f9fb",
            fg="#16202a",
        ).pack(anchor="w")

        tk.Label(
            frame,
            text=self.connection_url,
            font=("Consolas", 10),
            bg="#f7f9fb",
            fg="#2d6cdf",
        ).pack(anchor="w", pady=(6, 12))

        self.qr_photo = self.create_qr_photo()
        tk.Label(frame, image=self.qr_photo, bg="#f7f9fb").pack(pady=(0, 12))

        tk.Label(
            frame,
            textvariable=self.status_var,
            font=("Segoe UI", 9),
            bg="#f7f9fb",
            fg="#3f4b57",
        ).pack(anchor="w", pady=(0, 12))

        buttons = tk.Frame(frame, bg="#f7f9fb")
        buttons.pack(fill="x")
        tk.Button(buttons, text="Open Web UI", command=self.open_web_ui).pack(side="left")
        tk.Button(buttons, text="Copy URL", command=self.copy_url).pack(side="left", padx=8)
        tk.Button(buttons, text="Hide", command=self.hide_window).pack(side="right")

    def create_qr_photo(self) -> ImageTk.PhotoImage:
        qr = qrcode.QRCode(border=2, box_size=8)
        qr.add_data(self.connection_url)
        qr.make(fit=True)
        image = qr.make_image(fill_color="black", back_color="white").convert("RGB")
        return ImageTk.PhotoImage(image)

    def start(self) -> None:
        if self.is_port_available():
            self.zeroconf.register_service(self.service_info)
            self.service_registered = True
            self.server_started = True
            self.server_thread.start()
        else:
            self.status_var.set("Port 8000 is already in use. Exit the old Receiver and restart.")
        self.tray_icon.run_detached()
        self.show_window()
        self.root.mainloop()

    def is_port_available(self) -> bool:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.bind((HOST, PORT))
        except OSError:
            return False
        return True

    def run_server(self) -> None:
        self.server.run()
        if not self.server.should_exit:
            self.root.after(
                0,
                lambda: self.status_var.set(
                    "Receiver server stopped. Check whether port 8000 is already in use."
                ),
            )

    def show_window(self) -> None:
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def hide_window(self) -> None:
        self.root.withdraw()

    def open_web_ui(self) -> None:
        webbrowser.open(self.web_url)

    def copy_url(self) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(self.connection_url)
        self.status_var.set("Connection URL copied.")

    def show_window_from_tray(self, _icon: pystray.Icon, _item: pystray.MenuItem) -> None:
        self.root.after(0, self.show_window)

    def open_web_ui_from_tray(self, _icon: pystray.Icon, _item: pystray.MenuItem) -> None:
        self.root.after(0, self.open_web_ui)

    def copy_url_from_tray(self, _icon: pystray.Icon, _item: pystray.MenuItem) -> None:
        self.root.after(0, self.copy_url)

    def quit_from_tray(self, _icon: pystray.Icon, _item: pystray.MenuItem) -> None:
        self.root.after(0, self.quit)

    def quit(self) -> None:
        if self.server_started:
            self.server.should_exit = True
        if self.service_registered:
            self.zeroconf.unregister_service(self.service_info)
        self.zeroconf.close()
        self.tray_icon.stop()
        self.root.destroy()


def main() -> None:
    receiver = SmartMouseTrayApp()
    receiver.start()


if __name__ == "__main__":
    main()
