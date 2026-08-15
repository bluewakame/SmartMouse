param(
    [string]$Version = "0.1.0"
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

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
if (Test-Path $Zip) { Remove-Item $Zip -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

Copy-Item $Exe (Join-Path $Stage "SmartMouseReceiver.exe")
Copy-Item (Join-Path $Root "Start-SmartMouse.bat") (Join-Path $Stage "Start-SmartMouse.bat")
Copy-Item (Join-Path $Root "README-release-ja.txt") (Join-Path $Stage "README-ja.txt")

@"
SmartMouse Receiver
Version: v$Version
Build date: $(Get-Date -Format yyyy-MM-dd)
Package type: Portable Windows ZIP
Entry point: SmartMouseReceiver.exe
"@ | Set-Content (Join-Path $Stage "VERSION.txt") -Encoding utf8

$Hash = (Get-FileHash (Join-Path $Stage "SmartMouseReceiver.exe") -Algorithm SHA256).Hash
"$Hash  SmartMouseReceiver.exe" | Set-Content (Join-Path $Stage "CHECKSUMS-SHA256.txt") -Encoding ascii -NoNewline

Compress-Archive -Path $Stage -DestinationPath $Zip -CompressionLevel Optimal
Write-Host "Package complete: $Zip"
