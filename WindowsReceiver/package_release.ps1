param(
    [string]$Version = "0.5.4",
    [string]$CertificateThumbprint = "",
    [string]$DownloadUrl = "",
    [switch]$SignBundledBinaries
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Join-Path $Root "dist\SmartMouseReceiver"
$Exe = Join-Path $AppDir "SmartMouseReceiver.exe"
$PackageName = "SmartMouseReceiver-v$Version"
$Stage = Join-Path $Root "release\$PackageName"
$Zip = Join-Path $Root "release\$PackageName.zip"

if (-not (Test-Path $Exe)) {
    throw "dist\SmartMouseReceiver\SmartMouseReceiver.exe was not found. Run build_exe.bat first."
}
if (-not (Test-Path (Join-Path $AppDir "_internal"))) {
    throw "dist\SmartMouseReceiver\_internal がありません。onedirビルドになっていない可能性があります。"
}

# パッケージ名の -Version はコード側の APP_VERSION とは独立しているため、
# 名前だけが新しく中身が古いパッケージが作れてしまう。ここで実際の値を読み、
# 食い違っていればビルドを止める。
Push-Location $Root
try {
    $CodeJson = & python -c "import json, main, receiver_protocol; print(json.dumps({'app': main.APP_VERSION, 'protocol': receiver_protocol.PROTOCOL_VERSION}))"
    if ($LASTEXITCODE -ne 0) { throw "main.py からバージョンを読み取れませんでした。" }
} finally {
    Pop-Location
}
$Code = $CodeJson | ConvertFrom-Json

if ($Code.app -ne $Version) {
    throw "バージョン不一致: -Version は '$Version' ですが、main.py の APP_VERSION は '$($Code.app)' です。どちらかを揃えてください。"
}

Write-Host "Packaging code version $($Code.app) (protocol $($Code.protocol))"

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
if (Test-Path $Zip) { Remove-Item $Zip -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

# onedirビルドはexe単体では動かない。_internal ごとそのまま配る。
Copy-Item (Join-Path $AppDir "*") $Stage -Recurse -Force
$PackagedExe = Join-Path $Stage "SmartMouseReceiver.exe"
Copy-Item (Join-Path $Root "Start-SmartMouse.bat") (Join-Path $Stage "Start-SmartMouse.bat")
Copy-Item (Join-Path $Root "README-release-ja.txt") (Join-Path $Stage "README-ja.txt")
Copy-Item (Join-Path $Root "..\LICENSE") (Join-Path $Stage "LICENSE.txt")
# 同梱ライブラリの一覧はビルド環境から作り直す。GPLが混ざっていればここで止まる。
& python (Join-Path $Root "generate_notices.py") (Join-Path $Stage "THIRD-PARTY-NOTICES.txt")
if ($LASTEXITCODE -ne 0) { throw "THIRD-PARTY-NOTICES.txt を生成できませんでした。" }

if ($CertificateThumbprint) {
    $SignTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if (-not $SignTool) {
        throw "signtool.exe が見つかりません。Windows SDKをインストールしてください。"
    }

    $SignTargets = @($PackagedExe)
    if ($SignBundledBinaries) {
        # 同梱DLL/PYDまで署名すると信頼性は上がるが、タイムスタンプ取得のぶん時間がかかる。
        $SignTargets += Get-ChildItem -Path (Join-Path $Stage "_internal") -Recurse -File -Include *.dll, *.pyd |
            ForEach-Object { $_.FullName }
    }

    foreach ($Target in $SignTargets) {
        & $SignTool.Source sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 $CertificateThumbprint $Target
        if ($LASTEXITCODE -ne 0) { throw "コード署名に失敗しました: $Target" }
    }

    & $SignTool.Source verify /pa $PackagedExe
    if ($LASTEXITCODE -ne 0) { throw "コード署名の検証に失敗しました。" }
} else {
    Write-Warning "コード署名なしでパッケージします。SmartScreenの警告が出る可能性があります。"
}

$Hash = (Get-FileHash $PackagedExe -Algorithm SHA256).Hash

@"
SmartMouse Receiver
Version: v$Version
App version (code): $($Code.app)
Protocol version (code): $($Code.protocol)
Build date: $(Get-Date -Format yyyy-MM-dd)
Package type: Portable Windows folder (PyInstaller onedir, no UPX)
Entry point: SmartMouseReceiver.exe
Note: SmartMouseReceiver.exe は _internal フォルダーと同じ場所に置いたままにしてください。
"@ | Set-Content (Join-Path $Stage "VERSION.txt") -Encoding utf8

@{
    name = "SmartMouseReceiver"
    version = $Code.app
    sha256 = $Hash
    minimumWindows = "10"
    protocol = $Code.protocol
    downloadUrl = $DownloadUrl
} | ConvertTo-Json | Set-Content (Join-Path $Stage "release.json") -Encoding utf8

# 同梱ファイルが1つでも差し替わっていないことを確認できるよう、全ファイルを対象にする。
$ChecksumPath = Join-Path $Stage "CHECKSUMS-SHA256.txt"
$Prefix = $Stage.TrimEnd('\') + '\'
$Lines = Get-ChildItem -Path $Stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    $Relative = $_.FullName.Substring($Prefix.Length).Replace('\', '/')
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)  $Relative"
}
($Lines -join "`r`n") | Set-Content $ChecksumPath -Encoding ascii

Compress-Archive -Path $Stage -DestinationPath $Zip -CompressionLevel Optimal
Write-Host "Package complete: $Zip"
Write-Host "SmartMouseReceiver.exe SHA-256: $Hash"
