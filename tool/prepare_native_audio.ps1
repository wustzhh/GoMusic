[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

$cacheRoot = Join-Path $ProjectRoot 'build/native-audio-cache'
$windowsArchive = Join-Path $cacheRoot 'mpv-dev-x86_64-20260901.7z'
$windowsExtract = Join-Path $cacheRoot 'windows-mpv-dev'
$androidArchive = Join-Path $cacheRoot 'mpv-android-universal-release.apk'
$androidExtract = Join-Path $cacheRoot 'android-mpv-universal'
$androidLibRoot = Join-Path $ProjectRoot 'android/app/src/main/jniLibs'

$windowsUrl = 'https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260901/mpv-dev-x86_64-20260901-git-02a595ddc1.7z'
$windowsSha256 = '680FEAC97F2DA3721E331D6B10D2D0E3E02F1113BE068FAC06AFF7F833A165D4'
$androidUrl = 'https://github.com/mpv-android/mpv-android/releases/download/2026-08-11/app-default-universal-release.apk'
$androidSha256 = '5B59F3B1FD43D536EDF1D78D55F1F173970C3783DC1493DFAB7C7A9F3780BC3D'

function Get-VerifiedDownload {
    param(
        [string]$Url,
        [string]$Path,
        [string]$Sha256
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    if (Test-Path $Path) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
        if ($actual -eq $Sha256) { return }
        Remove-Item -LiteralPath $Path -Force
    }

    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path -TimeoutSec 120
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -ne $Sha256) {
        throw "SHA256 mismatch for $Path. Expected $Sha256, got $actual"
    }
}

function Expand-VerifiedArchive {
    param(
        [string]$Archive,
        [string]$Destination
    )

    $marker = Join-Path $Destination '.extracted'
    if (Test-Path $marker) { return }
    if (Test-Path $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & tar -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract $Archive" }
    New-Item -ItemType File -Path $marker -Force | Out-Null
}

Get-VerifiedDownload -Url $windowsUrl -Path $windowsArchive -Sha256 $windowsSha256
Expand-VerifiedArchive -Archive $windowsArchive -Destination $windowsExtract

$windowsDll = Join-Path $windowsExtract 'libmpv-2.dll'
if (-not (Test-Path $windowsDll)) { throw "Full Windows libmpv-2.dll was not found after extraction" }

Get-VerifiedDownload -Url $androidUrl -Path $androidArchive -Sha256 $androidSha256
Expand-VerifiedArchive -Archive $androidArchive -Destination $androidExtract

$abis = @('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')
$libraries = @(
    'libavcodec.so',
    'libavdevice.so',
    'libavfilter.so',
    'libavformat.so',
    'libavutil.so',
    'libc++_shared.so',
    'libmpv.so',
    'libswresample.so',
    'libswscale.so'
)

foreach ($abi in $abis) {
    $sourceDir = Join-Path $androidExtract "lib/$abi"
    $targetDir = Join-Path $androidLibRoot $abi
    if (-not (Test-Path $sourceDir)) { throw "ABI directory missing from Android archive: $abi" }
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    foreach ($library in $libraries) {
        $source = Join-Path $sourceDir $library
        if (-not (Test-Path $source)) { throw "Native library missing from Android archive: $abi/$library" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $targetDir $library) -Force
    }
}

Write-Host "Native audio libraries are ready."
Write-Host "Windows: $windowsDll"
Write-Host "Android: $androidLibRoot"
