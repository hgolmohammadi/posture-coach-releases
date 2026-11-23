# PostureCoach v1.0.0 - verified Windows release upload
# Source: official public distribution repository. Does not upload source code.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repository = 'hgolmohammadi/posture-coach-releases'
$tag = 'v1.0.0'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
$uat = Join-Path $downloads 'PostureCoach-1.0.0-UAT'
$staging = Join-Path $downloads 'PostureCoach-1.0.0-Publish'
$exeName = 'PostureCoach-1.0.0-Windows-Portable.exe'
$zipName = 'PostureCoach-1.0.0-Windows-Portable.zip'
$sourceExe = Join-Path $uat $exeName
$sourceZip = Join-Path $uat $zipName
$publishedExe = Join-Path $staging $exeName
$publishedZip = Join-Path $staging $zipName
$checksumFile = Join-Path $staging 'SHA256SUMS.txt'
$readmeFile = Join-Path $staging 'README-FA.txt'

Write-Host 'POSTURE_100_RELEASE_PREFLIGHT_BEGIN'
foreach ($file in @($sourceExe,$sourceZip)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "Missing build artifact: $file"
  }
}
if ((Get-Item -LiteralPath $sourceExe).Length -lt 50000000) {
  throw 'EXE appears too small. Refusing release.'
}
if ((Get-Item -LiteralPath $sourceZip).Length -lt 50000000) {
  throw 'ZIP appears too small. Refusing release.'
}

$exeHash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash.ToLowerInvariant()
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($sourceZip)
try {
  $entryMatches = @($archive.Entries | Where-Object { $_.Name -eq $exeName })
  if ($entryMatches.Count -ne 1) {
    throw 'Original UAT ZIP does not contain exactly one matching EXE.'
  }
  if ($entryMatches[0].Length -ne (Get-Item -LiteralPath $sourceExe).Length) {
    throw 'Original UAT ZIP EXE size mismatch.'
  }
  $stream = $entryMatches[0].Open()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $insideHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
  if ($insideHash -ne $exeHash) {
    throw 'EXE differs between UAT ZIP and standalone build. Publishing stopped.'
  }
} finally {
  $archive.Dispose()
}

New-Item -ItemType Directory -Force -Path $staging | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $publishedExe -Force

# This clean README intentionally removes pre-release UAT/testing instructions.
$readme = @'
PostureCoach v1.0.0 - نسخه رسمی ویندوز ۶۴ بیتی

راهنمای استفاده:
۱. فایل ZIP را از حالت فشرده خارج کنید.
۲. فایل PostureCoach-1.0.0-Windows-Portable.exe را اجرا کنید.
۳. در صورت تمایل، وب‌کم را فعال کنید و در وضعیت مناسب کالیبره کنید.
۴. پس از شناسایی پایدار چهره، زمان‌سنج حضور آغاز می‌شود.
۵. بخش روتین‌ها و کتابخانه حرکات تکی به‌صورت پیش‌فرض باز هستند.
۶. برای بستن کامل برنامه از دکمه خروج در صفحه اصلی استفاده کنید.

این نرم‌افزار برای آگاهی از وضعیت نشستن و مدیریت استراحت است و
جایگزین تشخیص یا درمان پزشکی نیست.

اطلاعات رسمی و پشتیبانی:
https://github.com/hgolmohammadi/posture-coach-releases
'@
[IO.File]::WriteAllText($readmeFile,$readme,(New-Object Text.UTF8Encoding($false)))
$tmpZip = Join-Path $staging 'PostureCoach-1.0.0-Windows-Portable.building.zip'
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force }
Compress-Archive -LiteralPath @($publishedExe,$readmeFile) -DestinationPath $tmpZip -CompressionLevel Optimal
$checkZip = [System.IO.Compression.ZipFile]::OpenRead($tmpZip)
try {
  $names = @($checkZip.Entries | ForEach-Object { $_.Name } | Sort-Object)
  if ($names.Count -ne 2 -or -not ($names -contains $exeName) -or -not ($names -contains 'README-FA.txt')) {
    throw 'Public ZIP does not have the two expected files.'
  }
} finally {
  $checkZip.Dispose()
}
Move-Item -LiteralPath $tmpZip -Destination $publishedZip -Force

$zipHash = (Get-FileHash -LiteralPath $publishedZip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllLines($checksumFile, @(
  "$exeHash  $exeName",
  "$zipHash  $zipName"
), (New-Object Text.UTF8Encoding($false)))

Write-Host "EXE_SHA256=$exeHash"
Write-Host "ZIP_SHA256=$zipHash"
Write-Host "RELEASE_STAGING=$staging"
Write-Host 'POSTURE_100_RELEASE_ARTIFACTS_VERIFIED'

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
  Write-Warning 'GitHub CLI not found. Install it once, then rerun this script:'
  Write-Host 'winget install --id GitHub.cli -e'
  throw 'GITHUB_CLI_NOT_INSTALLED'
}
& gh auth status -h github.com 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'GitHub sign-in required. A browser will open for authorization.'
  & gh auth login -h github.com -p https -w
  if ($LASTEXITCODE -ne 0) { throw 'GITHUB_AUTH_FAILED' }
}

$releaseId = 455344417  # Verified draft created on 2026-11-23
$viewText = & gh api "repos/$repository/releases/$releaseId"
if ($LASTEXITCODE -ne 0) { throw 'GITHUB_DRAFT_NOT_FOUND: Release should exist before upload.' }
$view = ($viewText -join [Environment]::NewLine) | ConvertFrom-Json
if ($view.tag_name -ne $tag) { throw 'Unexpected release identity. Publishing stopped.' }
if (-not $view.draft) { throw 'Release v1.0.0 is no longer draft. Stop to prevent accidental overwrites.' }

$paths = @($publishedExe,$publishedZip,$checksumFile)
$shaMap = @{
  $exeName = $exeHash
  $zipName = $zipHash
  'SHA256SUMS.txt' = (Get-FileHash -LiteralPath $checksumFile -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-RemoteAssets {
  $response = & gh api "repos/$repository/releases/$releaseId"
  if ($LASTEXITCODE -ne 0) { throw 'Failed to read GitHub release assets.' }
  return (($response -join [Environment]::NewLine) | ConvertFrom-Json).assets
}
$existing = @(Get-RemoteAssets)
foreach ($path in $paths) {
  $name = [IO.Path]::GetFileName($path)
  $entry = @($existing | Where-Object { $_.name -eq $name })
  if ($entry.Count -gt 1) { throw "Duplicate remote asset: $name" }
  if ($entry.Count -eq 1) {
    if ($entry[0].digest -ne ('sha256:' + $shaMap[$name])) {
      throw "Remote asset has different digest. Refusing to overwrite: $name"
    }
    Write-Host "ALREADY_VERIFIED=$name"
    continue
  }
  Write-Host "UPLOADING=$name"
  & gh release upload $tag $path --repo $repository
  if ($LASTEXITCODE -ne 0) { throw "UPLOAD_FAILED=$name" }
  $existing = @(Get-RemoteAssets)
}

$remote = @(Get-RemoteAssets)
foreach ($name in @($exeName,$zipName,'SHA256SUMS.txt')) {
  $entry = @($remote | Where-Object { $_.name -eq $name })
  if ($entry.Count -ne 1 -or $entry[0].digest -ne ('sha256:' + $shaMap[$name])) {
    throw "RELEASE_ASSET_VERIFICATION_FAILED=$name"
  }
}
Write-Host 'POSTURE_100_RELEASE_ASSETS_VERIFIED'

& gh release edit $tag --repo $repository --draft=false --latest
if ($LASTEXITCODE -ne 0) { throw 'RELEASE_PUBLICATION_FAILED' }
$latestResponse = & gh api "repos/$repository/releases/latest"
if ($LASTEXITCODE -ne 0) { throw 'LATEST_RELEASE_VERIFICATION_FAILED' }
$latest = ($latestResponse -join [Environment]::NewLine) | ConvertFrom-Json
if ($latest.tag_name -ne $tag) { throw "LATEST_RELEASE_MISMATCH=$($latest.tag_name)" }

Write-Host 'POSTURE_100_RELEASE_PUBLISHED'
Write-Host "RELEASE_URL=https://github.com/$repository/releases/tag/$tag"
Write-Host "LATEST_URL=https://github.com/$repository/releases/latest"
