[CmdletBinding()]
param(
    [string]$Organization = "https://dev.azure.com/OrbitalPM/",
    [string]$OutputPath = (Join-Path $PSScriptRoot "data.js"),
    [string]$PortfolioPath = (Join-Path $PSScriptRoot "portfolio.json"),
    [datetime]$StartDate = [datetime]"2026-10-12",
    [datetime]$EndDate = [datetime]"2026-10-16"
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$rosterIdentities = [ordered]@{
    "Guillermo Portillo"   = "guillermoportillo@esorbital.com"
    "Marcela Ramirez"      = "marcelaramirez@esorbital.com"
    "Carla España"         = "carlaespana@esorbital.com"
    "Fernando Galdamez"    = "fernandogaldamez@esorbital.com"
    "Oscar Lainez"         = "oscarlainez@esorbital.com"
    "Mauricio Dávila"      = "mauriciodavila@esorbital.com"
    "Hugo Ortiz"           = "hugoortiz@esorbital.com"
    "Manuel Galdamez"      = "manuelgaldamez@esorbital.com"
    "Manuel Martinez"      = "manuel.martinez@esorbital.com"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI no está instalado o no está disponible en PATH."
}

az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "No existe una sesión activa de Azure CLI. Ejecuta 'az login' e inténtalo nuevamente."
}

$weekStart = $StartDate.Date
$weekEnd = $EndDate.Date
$startText = $weekStart.ToString("yyyy-MM-dd")
$endText = $weekEnd.ToString("yyyy-MM-dd")
$organizationUri = $Organization.TrimEnd("/")
$organizationName = ([Uri]$Organization).Segments[-1].Trim("/")
$completedStates = @("closed", "done", "completed")

if (-not (Test-Path $PortfolioPath)) {
    throw "No se encontró el portafolio de Loop en '$PortfolioPath'."
}
$portfolioData = Get-Content $PortfolioPath -Raw -Encoding utf8 | ConvertFrom-Json
$portfolioProjects = @($portfolioData.projects)
if ($portfolioProjects.Count -eq 0) {
    throw "El portafolio de Loop no contiene proyectos."
}

function Test-PortfolioProjectClosed {
    param([object]$Project)
    return ($Project.status -eq "Closing") -or ([int]$Project.progress -ge 100)
}

$visiblePortfolioProjects = @($portfolioProjects | Where-Object { -not (Test-PortfolioProjectClosed $_) })
$closedPortfolioProjects = @($portfolioProjects | Where-Object { Test-PortfolioProjectClosed $_ })
Write-Host "Portafolio Loop: $($visiblePortfolioProjects.Count) vigentes, $($closedPortfolioProjects.Count) cerrados o completados (ocultos)" -ForegroundColor Cyan

$azureDevOpsResource = "499b84ac-1321-427f-aa17-267ca6975798"
$accessToken = az account get-access-token --resource $azureDevOpsResource --query accessToken --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
    throw "No se pudo obtener un token para Azure DevOps. Ejecuta 'az login' e inténtalo nuevamente."
}
$headers = @{ Authorization = "Bearer $accessToken" }

function Escape-WiqlValue {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Invoke-WiqlQuery {
    param([string]$Query)

    $body = @{ query = $Query } | ConvertTo-Json
    $result = Invoke-RestMethod `
        -Uri "$organizationUri/_apis/wit/wiql?api-version=7.1" `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $body
    return @($result.workItems.id)
}

function Get-WorkItemBatch {
    param([object[]]$Ids)

    if ($Ids.Count -eq 0) { return @() }

    $resultItems = @()
    $requestedFields = @(
        "System.Id",
        "System.Title",
        "System.TeamProject",
        "System.AssignedTo",
        "System.State",
        "System.IterationPath",
        "System.ChangedDate"
    )

    for ($index = 0; $index -lt $Ids.Count; $index += 200) {
        $lastIndex = [Math]::Min($index + 199, $Ids.Count - 1)
        $batchBody = @{
            ids    = @($Ids[$index..$lastIndex])
            fields = $requestedFields
        } | ConvertTo-Json

        $batchResult = Invoke-RestMethod `
            -Uri "$organizationUri/_apis/wit/workitemsbatch?api-version=7.1" `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json; charset=utf-8" `
            -Body $batchBody
        $resultItems += @($batchResult.value)
    }

    return $resultItems
}

function ConvertTo-TaskRecord {
    param([object]$WorkItem)

    $fields = $WorkItem.fields
    $assignedTo = $fields."System.AssignedTo"
    $email = [string]$assignedTo.uniqueName
    $canonicalName = $null
    foreach ($entry in $rosterIdentities.GetEnumerator()) {
        if ($entry.Value -eq $email) {
            $canonicalName = $entry.Key
            break
        }
    }
    if ($null -eq $canonicalName) { return $null }

    $project = [string]$fields."System.TeamProject"
    $state = [string]$fields."System.State"
    $iterationPath = [string]$fields."System.IterationPath"
    $sprint = if ($iterationPath.Contains("\")) {
        $iterationPath.Substring($iterationPath.LastIndexOf("\") + 1)
    }
    elseif ([string]::IsNullOrWhiteSpace($iterationPath)) { "Sin sprint" }
    else { $iterationPath }

    return [pscustomobject]@{
        id          = [int]$WorkItem.id
        title       = [string]$fields."System.Title"
        state       = $state
        isCompleted = $completedStates -contains $state.ToLowerInvariant()
        project     = $project
        sprint      = $sprint
        iteration   = $iterationPath
        changedDate = [string]$fields."System.ChangedDate"
        engineer    = $canonicalName
        email       = $email
        url         = "https://dev.azure.com/$organizationName/$([Uri]::EscapeDataString($project))/_workitems/edit/$($WorkItem.id)"
    }
}

function Get-ProjectIterations {
    param([string]$Project)

    $encodedProject = [Uri]::EscapeDataString($Project)
    try {
        $root = Invoke-RestMethod `
            -Uri "$organizationUri/$encodedProject/_apis/wit/classificationnodes/iterations?`$depth=20&api-version=7.1" `
            -Headers $headers
    }
    catch {
        Write-Warning "No se pudieron consultar las iteraciones de '$Project': $($_.Exception.Message)"
        return @()
    }

    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Node = $root; Prefix = "" })
    $iterations = @()

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $node = $current.Node
        $path = if ($current.Prefix) { "$($current.Prefix)\$($node.name)" } else { [string]$node.name }
        if ($node.attributes.startDate -and $node.attributes.finishDate) {
            $iterations += [pscustomobject]@{
                path   = $path
                name   = [string]$node.name
                start  = ([datetime]$node.attributes.startDate).Date
                finish = ([datetime]$node.attributes.finishDate).Date
            }
        }
        foreach ($child in @($node.children)) {
            if ($null -ne $child) {
                $queue.Enqueue([pscustomobject]@{ Node = $child; Prefix = $path })
            }
        }
    }

    return $iterations
}

$assignedClauses = @($rosterIdentities.Values | ForEach-Object {
    "[System.AssignedTo] = '$(Escape-WiqlValue $_)'"
}) -join " OR "

Write-Host "Consultando proyectos activos de los $($rosterIdentities.Count) ingenieros..." -ForegroundColor Cyan
$activeWiql = "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Task' AND ($assignedClauses) AND [System.State] NOT IN ('Removed','Closed','Done','Completed') ORDER BY [System.ChangedDate] DESC"
$activeIds = @(Invoke-WiqlQuery -Query $activeWiql)
$activeWorkItems = @(Get-WorkItemBatch -Ids $activeIds)
$activeTasks = @($activeWorkItems | ForEach-Object { ConvertTo-TaskRecord $_ } | Where-Object { $null -ne $_ })
$activeProjectNames = @($activeTasks.project | Sort-Object -Unique)
Write-Host "  $($activeTasks.Count) tareas activas en $($activeProjectNames.Count) proyectos" -ForegroundColor Green

$projectsResponse = Invoke-RestMethod -Uri "$organizationUri/_apis/projects?`$top=1000&api-version=7.1" -Headers $headers
$knownProjectNames = @($projectsResponse.value.name)
$portfolioAdoProjectNames = @(
    $visiblePortfolioProjects.adoProjects |
        Where-Object { $_ -and $_ -in $knownProjectNames } |
        Sort-Object -Unique
)
$unknownPortfolioMappings = @(
    $portfolioProjects.adoProjects |
        Where-Object { $_ -and $_ -notin $knownProjectNames } |
        Sort-Object -Unique
)
$currentActiveTasks = @($activeTasks | Where-Object project -In $portfolioAdoProjectNames)
$completedAdoProjectNames = @($activeProjectNames | Where-Object { $_ -notin $portfolioAdoProjectNames })

Write-Host "Resolviendo sprints que cruzan $startText a $endText..." -ForegroundColor Cyan
$weeklyIterations = @()
foreach ($project in $portfolioAdoProjectNames) {
    $projectIterations = @(Get-ProjectIterations -Project $project)
    $matches = @($projectIterations | Where-Object { $_.start -le $weekEnd -and $_.finish -ge $weekStart })
    foreach ($match in $matches) {
        $weeklyIterations += [pscustomobject]@{
            project = $project
            path    = $match.path
            name    = $match.name
            start   = $match.start.ToString("yyyy-MM-dd")
            finish  = $match.finish.ToString("yyyy-MM-dd")
        }
    }
}

$weeklyIdSet = [Collections.Generic.HashSet[int]]::new()
foreach ($projectGroup in @($weeklyIterations | Group-Object project)) {
    $project = $projectGroup.Name
    $iterationClauses = @($projectGroup.Group | ForEach-Object {
        "[System.IterationPath] = '$(Escape-WiqlValue $_.path)'"
    }) -join " OR "
    $weeklyWiql = "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Task' AND [System.TeamProject] = '$(Escape-WiqlValue $project)' AND ($assignedClauses) AND ($iterationClauses) AND [System.State] <> 'Removed'"
    foreach ($id in @(Invoke-WiqlQuery -Query $weeklyWiql)) {
        if ($null -ne $id -and [int]$id -gt 0) {
            [void]$weeklyIdSet.Add([int]$id)
        }
    }
}

$weeklyIds = @($weeklyIdSet)
$weeklyWorkItems = @(Get-WorkItemBatch -Ids $weeklyIds)
$weeklyTasks = @($weeklyWorkItems | ForEach-Object { ConvertTo-TaskRecord $_ } | Where-Object { $null -ne $_ })

$iterationLookup = @{}
foreach ($iteration in $weeklyIterations) {
    $iterationLookup["$($iteration.project)|$($iteration.path)"] = $iteration
}
foreach ($task in $weeklyTasks) {
    $iteration = $iterationLookup["$($task.project)|$($task.iteration)"]
    $task | Add-Member -NotePropertyName sprintStart -NotePropertyValue $iteration.start -Force
    $task | Add-Member -NotePropertyName sprintEnd -NotePropertyValue $iteration.finish -Force
}

$engineers = @(
    foreach ($identity in $rosterIdentities.GetEnumerator()) {
        $memberName = $identity.Key
        $email = $identity.Value
        $memberActiveTasks = @($currentActiveTasks | Where-Object email -EQ $email)
        $memberWeeklyTasks = @($weeklyTasks | Where-Object email -EQ $email)
        $memberPortfolioProjects = @($visiblePortfolioProjects | Where-Object { $memberName -in @($_.engineers) })
        $activeProjects = @(
            foreach ($portfolioProject in $memberPortfolioProjects) {
                $mappedNames = @($portfolioProject.adoProjects)
                $mappedTasks = @($memberActiveTasks | Where-Object project -In $mappedNames)
                [pscustomobject]@{
                    name            = "$($portfolioProject.client) - $($portfolioProject.scope)"
                    client          = $portfolioProject.client
                    scope           = $portfolioProject.scope
                    portfolioStatus = $portfolioProject.status
                    portfolioProgress = [int]$portfolioProject.progress
                    activeTaskCount = $mappedTasks.Count
                    adoProjects     = $mappedNames
                }
            }
        )
        $activeProjects = @($activeProjects | Sort-Object name)
        $weeklyProjects = @(
            foreach ($portfolioProject in $memberPortfolioProjects) {
                $mappedNames = @($portfolioProject.adoProjects)
                $projectTasks = @($memberWeeklyTasks | Where-Object project -In $mappedNames)
                if ($projectTasks.Count -eq 0) { continue }
                $completedCount = @($projectTasks | Where-Object isCompleted).Count
                $sprints = @(
                    $projectTasks |
                        Group-Object iteration |
                        ForEach-Object {
                            $sprintTasks = @($_.Group | Sort-Object title)
                            [pscustomobject]@{
                                name   = $sprintTasks[0].sprint
                                path   = $_.Name
                                start  = $sprintTasks[0].sprintStart
                                finish = $sprintTasks[0].sprintEnd
                                tasks  = $sprintTasks
                            }
                        } |
                        Sort-Object start, name
                )
                [pscustomobject]@{
                    name           = "$($portfolioProject.client) - $($portfolioProject.scope)"
                    taskCount      = $projectTasks.Count
                    completedCount = $completedCount
                    progress       = if ($projectTasks.Count) { [Math]::Round(($completedCount / $projectTasks.Count) * 100) } else { 0 }
                    sprints        = $sprints
                }
            }
        )
        $weeklyProjects = @($weeklyProjects | Sort-Object taskCount -Descending)
        $weeklyCompleted = @($memberWeeklyTasks | Where-Object isCompleted).Count

        [pscustomobject]@{
            name            = $memberName
            email           = $email
            projectCount    = $activeProjects.Count
            activeTaskCount = $memberActiveTasks.Count
            taskCount       = $memberWeeklyTasks.Count
            completedCount  = $weeklyCompleted
            progress        = if ($memberWeeklyTasks.Count) { [Math]::Round(($weeklyCompleted / $memberWeeklyTasks.Count) * 100) } else { 0 }
            activeProjects  = $activeProjects
            projects        = $weeklyProjects
        }
    }
)
$engineers = @($engineers | Sort-Object @{ Expression = "projectCount"; Descending = $true }, name)

$projects = @(
    foreach ($portfolioProject in $visiblePortfolioProjects) {
        $mappedNames = @($portfolioProject.adoProjects)
        $projectActiveTasks = @($currentActiveTasks | Where-Object project -In $mappedNames)
        $projectWeeklyTasks = @($weeklyTasks | Where-Object project -In $mappedNames)
        $completedCount = @($projectWeeklyTasks | Where-Object isCompleted).Count
        [pscustomobject]@{
            name            = "$($portfolioProject.client) - $($portfolioProject.scope)"
            client          = $portfolioProject.client
            scope           = $portfolioProject.scope
            portfolioStatus = $portfolioProject.status
            portfolioProgress = [int]$portfolioProject.progress
            engineers       = @($portfolioProject.engineers)
            engineerCount   = @($portfolioProject.engineers).Count
            activeTaskCount = $projectActiveTasks.Count
            taskCount       = $projectWeeklyTasks.Count
            completedCount  = $completedCount
            progress        = if ($projectWeeklyTasks.Count) { [Math]::Round(($completedCount / $projectWeeklyTasks.Count) * 100) } else { 0 }
            adoProjects     = $mappedNames
        }
    }
)
$portfolioStatusOrder = @{
    "In progress"      = 1
    "Starting"         = 2
    "Initial Planning" = 3
    "On Hold"          = 4
    "Closing"          = 5
}
$projects = @(
    $projects |
        Sort-Object @{ Expression = { $portfolioStatusOrder[$_.portfolioStatus] }; Descending = $false },
                    @{ Expression = "portfolioProgress"; Descending = $true },
                    name
)
$projectsWithoutWeeklySprint = @($projects | Where-Object taskCount -EQ 0 | Select-Object -ExpandProperty name)
$closedPortfolioProjectNames = @($closedPortfolioProjects | ForEach-Object { "$($_.client) - $($_.scope)" } | Sort-Object)
$portfolioAverageProgress = if ($projects.Count) {
    [Math]::Round((($projects | Measure-Object portfolioProgress -Average).Average))
}
else {
    0
}

$totalCompleted = @($weeklyTasks | Where-Object isCompleted).Count
$dashboard = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    organization = $Organization
    weekStart = $startText
    weekEnd = $endText
    criteria = "Loop define el portafolio vigente. Se ocultan los proyectos en estado Closing o con 100% de avance. Azure DevOps aporta tareas activas y sprints. Proyectos de Azure DevOps ausentes en el portafolio vigente de Loop se consideran completados."
    portfolioSource = $portfolioData.source
    roster = @($rosterIdentities.GetEnumerator() | ForEach-Object { [pscustomobject]@{ name = $_.Key; email = $_.Value } })
    projectsWithoutWeeklySprint = $projectsWithoutWeeklySprint
    completedAdoProjects = $completedAdoProjectNames
    closedPortfolioProjects = $closedPortfolioProjectNames
    unknownPortfolioMappings = $unknownPortfolioMappings
    summary = [ordered]@{
        engineerCount = $engineers.Count
        activeEngineerCount = @($engineers | Where-Object projectCount -GT 0).Count
        projectCount = $projects.Count
        closedProjectCount = $closedPortfolioProjects.Count
        activeTaskCount = $currentActiveTasks.Count
        taskCount = $weeklyTasks.Count
        completedCount = $totalCompleted
        progress = if ($weeklyTasks.Count) { [Math]::Round(($totalCompleted / $weeklyTasks.Count) * 100) } else { 0 }
        portfolioAverageProgress = $portfolioAverageProgress
        completedProjectCount = $completedAdoProjectNames.Count
        unmappedPortfolioCount = @($projects | Where-Object { @($_.adoProjects).Count -eq 0 }).Count
    }
    engineers = $engineers
    projects = $projects
}

$json = $dashboard | ConvertTo-Json -Depth 14 -Compress
$content = "window.DASHBOARD_DATA = $json;"
[IO.File]::WriteAllText($OutputPath, $content, [Text.UTF8Encoding]::new($false))

Write-Host "Dashboard actualizado:" -ForegroundColor Green
Write-Host "  $($engineers.Count) ingenieros del roster ($(@($engineers | Where-Object projectCount -GT 0).Count) con proyectos activos)"
Write-Host "  $($projects.Count) proyectos vigentes en Loop ($($closedPortfolioProjects.Count) ocultos por cierre/100%)"
Write-Host "  Avance global de portafolio: $portfolioAverageProgress%"
Write-Host "  $($currentActiveTasks.Count) tareas activas vinculadas"
Write-Host "  $($weeklyTasks.Count) tareas en sprints de la semana"
Write-Host "  $($completedAdoProjectNames.Count) proyectos ADO marcados completados por ausencia en Loop"
Write-Host "  $(@($projects | Where-Object { @($_.adoProjects).Count -eq 0 }).Count) proyectos Loop sin mapeo ADO"
if ($projectsWithoutWeeklySprint.Count) {
    Write-Host "  $($projectsWithoutWeeklySprint.Count) proyectos activos sin sprint fechado en el periodo" -ForegroundColor Yellow
}
Write-Host "  $OutputPath"
