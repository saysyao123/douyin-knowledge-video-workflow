[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Root,

    [int64]$MinimumBytes = 10000,

    [string]$OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootFull = (Resolve-Path -LiteralPath $Root).Path
$null = Get-Command ffprobe.exe -ErrorAction Stop
$null = Get-Command ffmpeg.exe -ErrorAction Stop
$files = @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Filter '*.mp4' | Sort-Object FullName)
$results = @()

foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($rootFull, $file.FullName)
    $record = [ordered]@{
        path = $file.FullName
        relative_path = $relative
        status = 'failed'
        bytes = $file.Length
        duration_seconds = $null
        width = $null
        height = $null
        format = $null
        video_codec = $null
        audio_codec = $null
        sha256 = $null
        ffmpeg_decode = $false
        error = $null
        checked_at = (Get-Date).ToString('o')
    }
    try {
        if ($file.Length -lt $MinimumBytes) {
            throw "文件过小：$($file.Length) bytes"
        }
        $probeJson = & ffprobe.exe -v error -show_entries 'format=format_name,duration:stream=codec_type,codec_name,width,height' -of json -- $file.FullName 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($probeJson -join ''))) {
            throw 'FFprobe 读取失败'
        }
        $probe = ($probeJson -join "`n") | ConvertFrom-Json
        $streams = @($probe.streams)
        $video = @($streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
        $audio = @($streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
        if ($null -eq $video -or $null -eq $audio) {
            throw '缺少视频流或音频流'
        }
        $record.duration_seconds = [math]::Round([double]$probe.format.duration, 3)
        $record.width = [int]$video.width
        $record.height = [int]$video.height
        $record.format = [string]$probe.format.format_name
        $record.video_codec = [string]$video.codec_name
        $record.audio_codec = [string]$audio.codec_name

        & ffmpeg.exe -v error -xerror -i $file.FullName -map 0:v:0 -map 0:a:0 -f null NUL 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'FFmpeg 全量解码失败'
        }
        $record.ffmpeg_decode = $true
        $record.sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $record.status = 'ok'
    }
    catch {
        $record.error = $_.Exception.Message
    }
    $results += [pscustomobject]$record
}

$summary = [pscustomobject]@{
    root = $rootFull
    checked_at = (Get-Date).ToString('o')
    file_count = $files.Count
    passed = @($results | Where-Object status -eq 'ok').Count
    failed = @($results | Where-Object status -ne 'ok').Count
    results = $results
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $outputFull = [System.IO.Path]::GetFullPath($OutputJson)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputFull -Encoding UTF8
}

$summary | Select-Object root, file_count, passed, failed, checked_at | Format-List | Out-String | Write-Output
if ($summary.failed -gt 0) {
    $results | Where-Object status -ne 'ok' | Select-Object relative_path, status, error | Format-Table -AutoSize | Out-String | Write-Output
    exit 1
}
