"""SmartMouse Receiverのアイコン画像を組み立てる。

タスクトレイのアイコンと、exeへ埋め込むアイコンリソースを同じ絵から作る。
アイコン付きのexeは素性が分かりやすく、SmartScreenの警告画面でも
発行元と一緒にユーザーへ提示される。
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ACCENT = "#34DB9F"
BACKGROUND = "#111416"
# 接続中のトレイアイコン。ひと目で「今つながっている」と分かるようにする。
CONNECTED = "#FF9F1C"

# 元の絵は64x64で描いてあるので、そこからの倍率で各座標を伸縮させる。
BASE_SIZE = 64
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)


def build_icon_image(size: int = BASE_SIZE, fill: str = ACCENT) -> Image.Image:
    scale = size / BASE_SIZE

    def box(*values: float) -> tuple[float, ...]:
        return tuple(value * scale for value in values)

    image = Image.new("RGBA", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(box(5, 5, 59, 59), radius=15 * scale, fill=fill)
    draw.ellipse(box(19, 16, 45, 42), fill=BACKGROUND)
    draw.rectangle(box(29, 37, 35, 52), fill=BACKGROUND)
    return image


def write_ico(path: Path) -> Path:
    """exeへ埋め込むための.icoを書き出し、そのパスを返す。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    image = build_icon_image(max(ICO_SIZES))
    image.save(path, format="ICO", sizes=[(size, size) for size in ICO_SIZES])
    return path
