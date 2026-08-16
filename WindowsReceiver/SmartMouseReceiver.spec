# -*- mode: python ; coding: utf-8 -*-
"""SmartMouse ReceiverのPyInstallerビルド定義。

Microsoft DefenderやSmartScreenの誤検知を減らすため、次を方針とする。

- ``onedir``でビルドする。``--onefile``の「起動のたびに自分を%TEMP%へ展開して実行する」
  挙動は、マルウェアのドロッパーと見分けが付かず、誤検知の主要因になる。
- UPX圧縮を行わない。実行ファイルの圧縮はヒューリスティックの減点対象になる。
- strip・難読化・暗号化を行わない。
- バージョン情報リソースとアイコンを埋め込み、発行元の分かるexeにする。

Defenderを回避・無効化する処理は入れない。誤検知が出た場合はMicrosoftへ
誤検知として提出し、正式配布版はコード署名で対応する。
"""

import re
import sys
from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules


SPEC_DIR = Path(SPECPATH).resolve()
if str(SPEC_DIR) not in sys.path:
    sys.path.insert(0, str(SPEC_DIR))

from app_icon import write_ico  # noqa: E402  SPEC_DIRをsys.pathへ入れてから読む


BUILD_DIR = SPEC_DIR / "build"


def read_app_version() -> tuple[str, tuple[int, int, int, int]]:
    """main.pyのAPP_VERSIONを唯一の版数として読む。"""
    source = (SPEC_DIR / "main.py").read_text(encoding="utf-8")
    match = re.search(r'^APP_VERSION\s*=\s*"([^"]+)"', source, re.MULTILINE)
    if match is None:
        raise SystemExit("main.py から APP_VERSION を読み取れませんでした。")
    text = match.group(1)
    numbers = [int(part) for part in text.split(".")]
    numbers = (numbers + [0, 0, 0, 0])[:4]
    return text, tuple(numbers)


def write_version_file(path: Path, version_text: str, version_tuple: tuple) -> Path:
    """exeへ埋め込むバージョン情報リソースを書き出す。"""
    dotted = ".".join(str(number) for number in version_tuple)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"""VSVersionInfo(
  ffi=FixedFileInfo(
    filevers={version_tuple},
    prodvers={version_tuple},
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0),
  ),
  kids=[
    StringFileInfo(
      [
        StringTable(
          "040904B0",
          [
            StringStruct("CompanyName", "SmartMouse"),
            StringStruct("FileDescription", "SmartMouse Receiver"),
            StringStruct("FileVersion", "{dotted}"),
            StringStruct("InternalName", "SmartMouseReceiver"),
            StringStruct("LegalCopyright", "Copyright (c) SmartMouse"),
            StringStruct("OriginalFilename", "SmartMouseReceiver.exe"),
            StringStruct("ProductName", "SmartMouse Receiver"),
            StringStruct("ProductVersion", "{version_text}"),
          ],
        )
      ]
    ),
    VarFileInfo([VarStruct("Translation", [0x0409, 1200])]),
  ],
)
""",
        encoding="utf-8",
    )
    return path


VERSION_TEXT, VERSION_TUPLE = read_app_version()
VERSION_PATH = write_version_file(BUILD_DIR / "version_info.txt", VERSION_TEXT, VERSION_TUPLE)
ICON_PATH = write_ico(BUILD_DIR / "icon.ico")

hidden_imports = collect_submodules("uvicorn") + collect_submodules("pystray")

# 配布物に入れる必要のない開発用・テスト用パッケージ。同梱物を減らすほど
# スキャン対象のバイナリが減り、誤検知の当たり所も減る。
excluded_modules = [
    "_distutils_hack",
    "_pytest",
    "iniconfig",
    "lib2to3",
    "matplotlib",
    "numpy",
    "pandas",
    "pip",
    "pluggy",
    "pydoc_data",
    "pytest",
    "setuptools",
    "test",
    "tkinter.test",
]

# スマホのブラウザ用アプリを同梱し、Receiver自身が8000番で配信できるようにする。
# 実行時は main.py の WEB_DIR（sys._MEIPASS/web）から読む。
web_datas = [("web", "web")] if (SPEC_DIR / "web" / "index.html").exists() else []
if not web_datas:
    print("WARNING: web/index.html が無いため、Webアプリを同梱せずにビルドします。")

a = Analysis(
    ["receiver_gui.py"],
    pathex=[],
    binaries=[],
    datas=web_datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excluded_modules,
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SmartMouseReceiver",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ICON_PATH),
    version=str(VERSION_PATH),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="SmartMouseReceiver",
)
