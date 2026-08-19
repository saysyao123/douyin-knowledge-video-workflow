[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Manifest,

    [string]$OutputRoot = 'D:\整体视频流程重建\素材库\对标账号视频',

    [int64]$MinimumBytes = 10000,

    [switch]$Overwrite,

    [string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeLeafName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $leaf = [System.IO.Path]::GetFileName($Name)
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -ne $Name -or $leaf.Contains('..')) {
        throw "文件名不安全：$Name"
    }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalid) {
        if ($leaf.Contains([string]$char)) {
            throw "文件名包含非法字符：$Name"
        }
    }
    return $leaf
}

function Get-SafeFolderName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $clean = $Name.Trim()
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $clean = $clean.Replace([string]$char, '_')
    }
    $clean = $clean.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($clean) -or $clean -in @('.', '..')) {
        return '未命名账号'
    }
    return $clean
}

function Test-PublicDouyinMediaUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $parsed = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsed)) {
        return $false
    }
    if ($parsed.Scheme -ne 'https') {
        return $false
    }
    $host = $parsed.Host.ToLowerInvariant()
    $allowedHost = ($host -eq 'douyinvod.com' -or $host.EndsWith('.douyinvod.com') -or $host -eq 'www.douyin.com')
    if (-not $allowedHost) {
        return $false
    }
    if ($host -eq 'www.douyin.com' -and $parsed.AbsolutePath -notmatch '/aweme/v1/play') {
        return $false
    }
    return $true
}

function Get-BasicVideoInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $probeJson = & ffprobe.exe -v error -show_entries 'format=format_name,duration:stream=codec_type,codec_name,width,height' -of json -- $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($probeJson -join ''))) {
        throw "FFprobe 无法读取媒体：$Path"
    }
    $probe = ($probeJson -join "`n") | ConvertFrom-Json
    $streams = @($probe.streams)
    $video = @($streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
    $audio = @($streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
    if ($null -eq $video -or $null -eq $audio) {
        throw "缺少视频流或音频流：$Path"
    }
    return [pscustomobject]@{
        format = [string]$probe.format.format_name
        duration_seconds = [double]$probe.format.duration
        width = [int]$video.width
        height = [int]$video.height
        video_codec = [string]$video.codec_name
        audio_codec = [string]$audio.codec_name
    }
}

$null = Get-Command curl.exe -ErrorAction Stop
$null = Get-Command ffprobe.exe -ErrorAction Stop
$manifestFull = (Resolve-Path -LiteralPath $Manifest).Path
$rootFull = [System.IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $rootFull -Force

$rawManifest = Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8 | ConvertFrom-Json
$items = if ($rawManifest -is [System.Array]) { @($rawManifest) } elseif ($null -ne $rawManifest.items) { @($rawManifest.items) } else { @($rawManifest) }
$results = @()

foreach ($item in $items) {
    $id = [string]$item.aweme_id
    $account = [string]$item.account
    $accountFolder = if ($item.account_folder) { Get-SafeFolderName ([string]$item.account_folder) } else { Get-SafeFolderName $account }
    $mediaUrl = [string]$item.media_url
    $sourceUrl = [string]$item.source_url
    $filename = if ($item.filename) { Get-SafeLeafName ([string]$item.filename) } else { Get-SafeLeafName ("$id.mp4") }
    $targetDir = Join-Path $rootFull $accountFolder
    $targetPath = Join-Path $targetDir $filename
    $partPath = "$targetPath.part"
    $record = [ordered]@{
        account = $account
        aweme_id = $id
        title = [string]$item.title
        source_url = $sourceUrl
        target_path = $targetPath
        status = 'pending'
        error = $null
        bytes = $null
        duration_seconds = $null
        width = $null
        height = $null
        video_codec = $null
        audio_codec = $null
        sha256 = $null
        downloaded_at = (Get-Date).ToString('o')
    }

    try {
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($sourceUrl)) {
            throw '清单缺少 aweme_id 或 source_url'
        }
        if (-not (Test-PublicDouyinMediaUrl $mediaUrl)) {
            $record.status = 'media-url-rejected'
            $record.error = 'media_url 不是允许的抖音公开媒体地址，未尝试第三方解析。'
            $results += [pscustomobject]$record
            continue
        }
        $null = New-Item -ItemType Directory -Path $targetDir -Force

        if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and -not $Overwrite) {
            $existing = Get-BasicVideoInfo $targetPath
            $existingBytes = (Get-Item -LiteralPath $targetPath).Length
            if ($existingBytes -ge $MinimumBytes) {
                $record.status = 'skipped-existing-valid'
                $record.bytes = $existingBytes
                $record.duration_seconds = $existing.duration_seconds
                $record.width = $existing.width
                $record.height = $existing.height
                $record.video_codec = $existing.video_codec
                $record.audio_codec = $existing.audio_codec
                $record.sha256 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
                $results += [pscustomobject]$record
                continue
            }
            throw '目标文件已存在但未达到最小大小阈值；如需重下请显式使用 -Overwrite。'
        }

        if (Test-Path -LiteralPath $partPath) {
            Remove-Item -LiteralPath $partPath -Force
        }
        $curlArgs = @(
            '--fail', '--location', '--silent', '--show-error',
            '--retry', '2', '--retry-delay', '1', '--max-time', '180',
            '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36',
            '--referer', 'https://www.douyin.com/',
            '--output', $partPath,
            $mediaUrl
        )
        $curlOutput = & curl.exe @curlArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "curl 下载失败：$($curlOutput -join ' ')"
        }
        if (-not (Test-Path -LiteralPath $partPath -PathType Leaf)) {
            throw '下载未生成临时文件'
        }
        $partBytes = (Get-Item -LiteralPath $partPath).Length
        if ($partBytes -lt $MinimumBytes) {
            throw "临时文件过小：$partBytes bytes"
        }
        $info = Get-BasicVideoInfo $partPath
        if ($Overwrite -and (Test-Path -LiteralPath $targetPath)) {
            Remove-Item -LiteralPath $targetPath -Force
        }
        Move-Item -LiteralPath $partPath -Destination $targetPath -Force
        $hash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        $record.status = 'downloaded-basic-validated'
        $record.bytes = (Get-Item -LiteralPath $targetPath).Length
        $record.duration_seconds = $info.duration_seconds
        $record.width = $info.width
        $record.height = $info.height
        $record.video_codec = $info.video_codec
        $record.audio_codec = $info.audio_codec
        $record.sha256 = $hash
    }
    catch {
        $record.status = if ($record.status -eq 'pending') { 'download-failed' } else { $record.status }
        $record.error = $_.Exception.Message
        if (Test-Path -LiteralPath $partPath) {
            Remove-Item -LiteralPath $partPath -Force -ErrorAction SilentlyContinue
        }
    }
    $results += [pscustomobject]$record
}

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path (Split-Path -Parent $manifestFull) '下载结果.json'
}
$resultFull = [System.IO.Path]::GetFullPath($ResultPath)
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $resultFull) -Force
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultFull -Encoding UTF8

$results | Select-Object account, aweme_id, status, target_path, bytes, sha256, error | Format-Table -AutoSize | Out-String | Write-Output
if (@($results | Where-Object { $_.status -in @('downloaded-basic-validated', 'skipped-existing-valid') }).Count -ne $items.Count) {
    exit 1
}
