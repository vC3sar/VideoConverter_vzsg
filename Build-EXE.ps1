param(
    [string]$OutputName = "VideoConverter_VZSG.exe"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root "TVVideoConverter.ps1"
$output = Join-Path $root $OutputName

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " VideoConverter VZSG - Build EXE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $source)) {
    throw "No se encontró: $source"
}

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "PS2EXE no está instalado. Instalando en CurrentUser..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
    Import-Module ps2exe -Force
}

$params = @{
    inputFile   = $source
    outputFile  = $output
    noConsole   = $true
    x64         = $true
    STA         = $true
    DPIAware    = $true
    title       = "VideoConverter VZSG"
    description = "Portable multi-profile video converter by VazquezSG"
    product     = "VideoConverter VZSG"
    company     = "VazquezSG"
    version     = "1.1.2.0"
}

$icon = Join-Path $root "TVVideoConverter.ico"
if (Test-Path -LiteralPath $icon) {
    $params.iconFile = $icon
}

Write-Host "Compilando..." -ForegroundColor Green
Invoke-ps2exe @params

Write-Host ""
Write-Host "EXE creado:" -ForegroundColor Green
Write-Host $output -ForegroundColor White
Write-Host ""
Write-Host "Nota: FFmpeg NO se incrusta en el EXE. Si no está disponible, la app lo descarga automáticamente al primer uso." -ForegroundColor Yellow
