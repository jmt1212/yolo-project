<#
.SYNOPSIS
  Menjalankan PetraPark: backend (port 8001) dan aplikasi web (port 5600) sekaligus.

.DESCRIPTION
  Keduanya berjalan di jendela ini. Tekan Ctrl+C untuk menghentikan keduanya.

.PARAMETER Build
  Bangun ulang aplikasi web dulu (butuh Flutter). Pakai ini setelah mengubah kode di parking_ui\lib.

.PARAMETER NoBrowser
  Jangan buka browser secara otomatis.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\start.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\start.ps1 -Build
#>
param(
  [switch]$Build,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$webDir = Join-Path $root 'parking_ui\build\web'

function Fail($message) {
  Write-Host $message -ForegroundColor Red
  exit 1
}

# Python: .venv di root (clone baru, lihat README) atau trial1\.venv (pemasangan lama).
$python = @(
  (Join-Path $root '.venv\Scripts\python.exe'),
  (Join-Path $root 'trial1\.venv\Scripts\python.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $python) {
  Fail ("Python environment tidak ditemukan. Siapkan dulu:`n" +
        "  python -m venv .venv`n" +
        "  .\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt")
}

foreach ($port in 8001, 5600) {
  if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
    Fail "Port $port sedang dipakai. Hentikan aplikasi yang memakainya (mungkin PetraPark yang sudah berjalan), lalu coba lagi."
  }
}

# Aplikasi web dibangun jika diminta atau belum pernah dibangun.
if ($Build -or -not (Test-Path (Join-Path $webDir 'index.html'))) {
  $flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
  if (-not $flutter) {
    $flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
    if (-not (Test-Path $flutter)) { Fail 'Flutter tidak ditemukan. Pasang Flutter atau tambahkan folder bin-nya ke PATH.' }
  }
  Write-Host 'Membangun aplikasi web (sekitar 1 menit)...' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'parking_ui')
  try {
    & $flutter build web
    if ($LASTEXITCODE -ne 0) { Fail 'Gagal membangun aplikasi web.' }
  } finally {
    Pop-Location
  }
}

$backend = $null
$web = $null
try {
  Write-Host 'Menjalankan backend di http://127.0.0.1:8001 ...' -ForegroundColor Cyan
  $backend = Start-Process -FilePath $python -ArgumentList 'main.py' `
    -WorkingDirectory (Join-Path $root 'backend') -NoNewWindow -PassThru

  Write-Host 'Menjalankan aplikasi web di http://localhost:5600 ...' -ForegroundColor Cyan
  $web = Start-Process -FilePath $python `
    -ArgumentList '-m', 'http.server', '5600', '--bind', '127.0.0.1', '--directory', "`"$webDir`"" `
    -NoNewWindow -PassThru

  # Tunggu backend siap (memuat model YOLO butuh beberapa detik).
  $ready = $false
  for ($i = 0; $i -lt 90 -and -not $backend.HasExited; $i++) {
    try {
      Invoke-WebRequest 'http://127.0.0.1:8001/api/health' -UseBasicParsing -TimeoutSec 2 | Out-Null
      $ready = $true
      break
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  if (-not $ready) { Fail 'Backend tidak berhasil dijalankan. Lihat pesan error di atas.' }

  Write-Host ''
  Write-Host 'PetraPark siap: http://localhost:5600' -ForegroundColor Green
  Write-Host 'Tekan Ctrl+C untuk menghentikan backend dan aplikasi web.' -ForegroundColor Green
  Write-Host ''
  if (-not $NoBrowser) { Start-Process 'http://localhost:5600' }

  while (-not $backend.HasExited -and -not $web.HasExited) {
    Start-Sleep -Seconds 1
  }
  if ($backend.HasExited) { Write-Host 'Backend berhenti.' -ForegroundColor Yellow }
  if ($web.HasExited) { Write-Host 'Aplikasi web berhenti.' -ForegroundColor Yellow }
} finally {
  # Dijalankan juga saat Ctrl+C: pastikan keduanya ikut berhenti.
  foreach ($proc in $backend, $web) {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
  }
  Write-Host 'PetraPark dihentikan.' -ForegroundColor Cyan
}
