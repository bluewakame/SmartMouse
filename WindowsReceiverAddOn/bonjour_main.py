"""SmartMouse ReceiverをBonjour自動検出付きで起動します。

既存のmain.pyと同じフォルダーへこのファイルをコピーし、
`python bonjour_main.py` で起動してください。
"""

import socket

import qrcode
import uvicorn
from zeroconf import IPVersion, ServiceInfo, Zeroconf

from main import HOST, PAIRING_TOKEN, PORT, app, get_lan_ip, print_startup_banner


def main() -> None:
    ip_address = get_lan_ip()
    encoded_ip = ip_address.replace(".", "-")
    service_type = "_smartmouse._tcp.local."
    # iPhoneアプリはサービス名末尾の合言葉を読み取って接続するため、必ず含める。
    info = ServiceInfo(
        service_type,
        f"SmartMouse-{encoded_ip}-{PAIRING_TOKEN}.{service_type}",
        addresses=[socket.inet_aton(ip_address)],
        port=PORT,
        properties={"path": "/ws", "token": PAIRING_TOKEN},
        server=f"smartmouse-{encoded_ip}.local.",
    )
    zeroconf = Zeroconf(ip_version=IPVersion.V4Only)

    try:
        zeroconf.register_service(info)
        print_startup_banner()
        print("iPhone app auto-discovery: enabled")
        connection_url = f"ws://{ip_address}:{PORT}/ws?token={PAIRING_TOKEN}"
        print()
        print("Scan this QR code with the SmartMouse iPhone app:")
        qr = qrcode.QRCode(border=1)
        qr.add_data(connection_url)
        qr.make(fit=True)
        qr.print_ascii(invert=True)
        print(connection_url)
        print()
        uvicorn.run(app, host=HOST, port=PORT, log_level="info")
    finally:
        zeroconf.unregister_service(info)
        zeroconf.close()


if __name__ == "__main__":
    main()
