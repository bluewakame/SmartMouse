param(
    [string]$Version = "0.4.0",
    [string]$CertificateThumbprint = "",
    [string]$DownloadUrl = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Root "dist\SmartMouseReceiver.exe"
$PackageName = "SmartMouseReceiver-v$Version"
$Stage = Join-Path $Root "release\$PackageName"
$Zip = Join-Path $Root "release\$PackageName.zip"

if (-not (Test-Path $Exe)) {
    throw "dist\SmartMouseReceiver.exe was not found. Run build_exe.bat first."
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

$PackagedExe = Join-Path $Stage "SmartMouseReceiver.exe"
Copy-Item $Exe $PackagedExe
Copy-Item (Join-Path $Root "Start-SmartMouse.bat") (Join-Path $Stage "Start-SmartMouse.bat")
Copy-Item (Join-Path $Root "README-release-ja.txt") (Join-Path $Stage "README-ja.txt")

if ($CertificateThumbprint) {
    $SignTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if (-not $SignTool) {
        throw "signtool.exe が見つかりません。Windows SDKをインストールしてください。"
    }
    & $SignTool.Source sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 $CertificateThumbprint $PackagedExe
    if ($LASTEXITCODE -ne 0) { throw "コード署名に失敗しました。" }
    & $SignTool.Source verify /pa $PackagedExe
    if ($LASTEXITCODE -ne 0) { throw "コード署名の検証に失敗しました。" }
}

@"
SmartMouse Receiver
Version: v$Version
App version (code): $($Code.app)
Protocol version (code): $($Code.protocol)
Build date: $(Get-Date -Format yyyy-MM-dd)
Package type: Portable Windows ZIP
Entry point: SmartMouseReceiver.exe
"@ | Set-Content (Join-Path $Stage "VERSION.txt") -Encoding utf8

$Hash = (Get-FileHash $PackagedExe -Algorithm SHA256).Hash
"$Hash  SmartMouseReceiver.exe" | Set-Content (Join-Path $Stage "CHECKSUMS-SHA256.txt") -Encoding ascii -NoNewline

@{
    name = "SmartMouseReceiver"
    version = $Code.app
    sha256 = $Hash
    minimumWindows = "10"
    protocol = $Code.protocol
    downloadUrl = $DownloadUrl
} | ConvertTo-Json | Set-Content (Join-Path $Stage "release.json") -Encoding utf8

Compress-Archive -Path $Stage -DestinationPath $Zip -CompressionLevel Optimal
Write-Host "Package complete: $Zip"
