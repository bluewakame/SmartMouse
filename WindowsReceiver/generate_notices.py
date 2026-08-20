"""配布物へ同梱する THIRD-PARTY-NOTICES.txt を、ビルド環境から生成する。

手書きの一覧は必ず古くなる。依存を足した人が notices を直し忘れても気付けるよう、
ビルドのたびに実際の導入済みパッケージから作り直す。

同時に、配布できないライセンスが紛れ込んでいないかを検査して、見つかれば
ビルドを止める。PyAutoGUI は MouseInfo と PyMsgBox（どちらも GPLv3）を
依存に持つが、``alert()`` や ``mouseInfo()`` を呼ばない限り不要なので
spec の ``excludes`` で外している。GPL は LGPL と違い、同梱して配布すると
配布物全体へ及ぶため、うっかり戻ると配布条件が変わってしまう。

    python generate_notices.py THIRD-PARTY-NOTICES.txt
"""

from __future__ import annotations

import sys
from importlib.metadata import Distribution, distributions
from pathlib import Path


# ビルドにしか使わず、配布物へは入らないもの。
BUILD_ONLY = {
    "altgraph",
    "packaging",
    "pefile",
    "pip",
    "pyinstaller",
    "pyinstaller-hooks-contrib",
    "pywin32-ctypes",
    "setuptools",
    "wheel",
}

# spec の excludes で外しているもの。ここに残っていても配布物には入らない。
EXCLUDED_AT_BUILD = {"mouseinfo", "pymsgbox"}

LICENSE_FILE_HINTS = ("LICENSE", "LICENCE", "COPYING", "NOTICE")


def normalize(name: str) -> str:
    return name.lower().replace("_", "-")


def license_of(dist: Distribution) -> str:
    """パッケージのライセンス表記を、確からしい順に拾う。"""
    metadata = dist.metadata
    expression = metadata.get("License-Expression")
    if expression:
        return expression.strip()
    classifiers = [
        line.split("::")[-1].strip()
        for line in metadata.get_all("Classifier") or []
        if line.startswith("License")
    ]
    if classifiers:
        return " / ".join(classifiers)
    declared = (metadata.get("License") or "").strip()
    if declared:
        # 全文を License: へ書いてしまう配布物があるので、1行目だけ見る。
        return declared.splitlines()[0].strip()
    return "(表記なし)"


def license_text_of(dist: Distribution) -> str:
    """dist-info に同梱されたライセンス全文。無ければ空文字。"""
    texts: list[str] = []
    for path in dist.files or []:
        name = Path(path.name).stem.upper()
        if not any(name.startswith(hint) for hint in LICENSE_FILE_HINTS):
            continue
        try:
            body = path.read_text()
        except (OSError, UnicodeDecodeError):
            continue
        if body.strip():
            texts.append(f"--- {path.name} ---\n{body.strip()}")
    return "\n\n".join(texts)


def is_forbidden(license_name: str) -> bool:
    """配布物全体へ影響が及ぶライセンスか（GPL。LGPLは対象外）。"""
    lowered = license_name.lower()
    if "lesser" in lowered or "lgpl" in lowered:
        return False
    return "gpl" in lowered or "general public license" in lowered


def collect() -> list[tuple[str, str, str, str, str]]:
    rows = []
    seen = set()
    for dist in distributions():
        name = dist.metadata["Name"]
        if not name:
            continue
        key = normalize(name)
        if key in BUILD_ONLY or key in EXCLUDED_AT_BUILD or key in seen:
            continue
        seen.add(key)
        homepage = (
            dist.metadata.get("Home-page")
            or next(
                (
                    line.split(",", 1)[1].strip()
                    for line in dist.metadata.get_all("Project-URL") or []
                    if line.lower().startswith(("homepage", "source", "repository"))
                ),
                "",
            )
        )
        rows.append(
            (name, dist.version or "", license_of(dist), homepage, license_text_of(dist))
        )
    return sorted(rows, key=lambda row: row[0].lower())


def render(rows: list[tuple[str, str, str, str, str]]) -> str:
    lines = [
        "SmartMouse Receiver — 同梱しているソフトウェアのライセンス",
        "=" * 62,
        "",
        "SmartMouseReceiver.exe には、下記のオープンソースソフトウェアと",
        "Python 本体（PSF License）が同梱されています。それぞれの著作権は",
        "各権利者に帰属し、以下のライセンスの下で配布されています。",
        "",
        "このファイルはビルド時に generate_notices.py が自動生成しています。",
        "",
        "LGPL のライブラリ（pystray, zeroconf）について:",
        "  本配布物は PyInstaller の onedir 形式で、これらは _internal フォルダー内に",
        "  個別のファイルとして置かれています。利用者が同じバージョンのライブラリへ",
        "  差し替えて実行することが可能です。各ライブラリのソースコードは、下記の",
        "  配布元および PyPI から取得できます。",
        "",
        "=" * 62,
        "",
    ]
    for name, version, license_name, homepage, text in rows:
        lines.append(f"* {name} {version}")
        lines.append(f"  ライセンス: {license_name}")
        if homepage:
            lines.append(f"  配布元: {homepage}")
        lines.append("")
    lines.append("=" * 62)
    lines.append("ライセンス全文")
    lines.append("=" * 62)
    lines.append("")
    for name, version, license_name, _homepage, text in rows:
        lines.append("-" * 62)
        lines.append(f"{name} {version} — {license_name}")
        lines.append("-" * 62)
        lines.append("")
        lines.append(text if text else "(パッケージにライセンス全文が同梱されていません)")
        lines.append("")
    return "\n".join(lines) + "\n"


def main() -> None:
    destination = Path(sys.argv[1] if len(sys.argv) > 1 else "THIRD-PARTY-NOTICES.txt")
    rows = collect()

    forbidden = [(name, lic) for name, _v, lic, _h, _t in rows if is_forbidden(lic)]
    if forbidden:
        print("配布できないライセンスのパッケージが同梱対象に入っています:", file=sys.stderr)
        for name, lic in forbidden:
            print(f"  - {name}: {lic}", file=sys.stderr)
        print(
            "\nGPL は LGPL と違い、同梱して配布すると配布物全体へ及びます。\n"
            "使っていないなら SmartMouseReceiver.spec の excludes へ足してください。",
            file=sys.stderr,
        )
        raise SystemExit(1)

    destination.write_text(render(rows), encoding="utf-8")
    print(f"{destination} を書き出しました（{len(rows)} パッケージ）")


if __name__ == "__main__":
    main()
