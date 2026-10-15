[CmdletBinding()]
param(
    [switch]$SinActualizar
)

$ErrorActionPreference = "Stop"

if (-not $SinActualizar) {
    & (Join-Path $PSScriptRoot "ActualizarDatos.ps1")
}

Start-Process (Join-Path $PSScriptRoot "index.html")
Write-Host ""
Write-Host "Tip: ejecuta .\ProgramarActualizacion.ps1 una sola vez para que data.js se actualice solo cada 15 minutos." -ForegroundColor Cyan
Write-Host "El dashboard, una vez abierto, revisa data.js cada 60 segundos y se recarga solo cuando detecta cambios." -ForegroundColor Cyan
