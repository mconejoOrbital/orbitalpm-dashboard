[CmdletBinding(DefaultParameterSetName = "Register")]
param(
    [Parameter(ParameterSetName = "Register")]
    [int]$IntervalMinutes = 15,

    [Parameter(ParameterSetName = "Remove")]
    [switch]$Remove,

    [string]$TaskName = "OrbitalPM-DashboardSync"
)

$ErrorActionPreference = "Stop"

if ($Remove) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-Host "No existe la tarea programada '$TaskName'." -ForegroundColor Yellow
        return
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tarea programada '$TaskName' eliminada. El dashboard ya no se sincronizará automáticamente." -ForegroundColor Green
    return
}

if ($IntervalMinutes -lt 5) {
    throw "El intervalo mínimo recomendado es de 5 minutos para no saturar Azure DevOps."
}

$scriptPath = Join-Path $PSScriptRoot "ActualizarDatos.ps1"
if (-not (Test-Path $scriptPath)) {
    throw "No se encontró '$scriptPath'."
}

$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshPath) {
    $pwshPath = (Get-Command powershell).Source
}

$action = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $PSScriptRoot

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Actualiza data.js del Dashboard OrbitalPM consultando Azure DevOps cada $IntervalMinutes minutos." `
    -ErrorAction Stop `
    | Out-Null

Write-Host "Tarea programada '$TaskName' creada: se ejecutará cada $IntervalMinutes minutos." -ForegroundColor Green
Write-Host "Requiere que az CLI tenga una sesión activa (ejecuta 'az login' si expira)." -ForegroundColor Yellow
Write-Host "Para quitarla: .\ProgramarActualizacion.ps1 -Remove" -ForegroundColor Cyan
