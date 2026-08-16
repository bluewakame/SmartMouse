$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue

if (-not (Test-Path (Join-Path $Root "dist\SmartMouseReceiver\SmartMouseReceiver.exe"))) {
    throw "dist\SmartMouseReceiver\SmartMouseReceiver.exe がありません。先に build_exe.bat を実行してください。"
}
if (-not (Test-Path (Join-Path $Root "dist\SmartMouseReceiver\_internal"))) {
    throw "dist\SmartMouseReceiver\_internal がありません。onedirビルドになっていない可能性があります。"
}
if (-not $Compiler) {
    throw "Inno Setup 6 が見つかりません。https://jrsoftware.org/isdl.php からインストールしてください。"
}

& $Compiler.Source (Join-Path $Root "SmartMouseReceiver.iss")
if ($LASTEXITCODE -ne 0) { throw "インストーラー作成に失敗しました。" }
Write-Host "Installer complete: $Root\installer"
