param(
    [string]$RepoPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ConnectionName = "JD45494",
    [string]$Database = "READINESSOPS_REVISION_DEV",
    [string]$Schema = "APP",
    [string]$Warehouse = "READINESSOPS_WH",
    [string]$Role = "ACCOUNTADMIN",
    [string]$AppName = "READINESSOPS_REVISION_DASHBOARD",
    [string]$StageName = "READINESSOPS_REVISION_STAGE",
    [string]$ViewerRole = "READINESSOPS_EVALUATOR",
    [switch]$DeployApp
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    throw "Git repository not found: $RepoPath"
}

$sqlFiles = @(
    "sql\33_evidence_impact_foundation.sql",
    "sql\34_evidence_impact_procedure.sql",
    "sql\35_evidence_impact_validation.sql"
)

foreach ($relativePath in $sqlFiles) {
    $fullPath = Join-Path $RepoPath $relativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        throw "Required SQL file not found: $fullPath"
    }
}

Write-Host "Deploying Evidence impact analysis objects..." -ForegroundColor Cyan
foreach ($relativePath in $sqlFiles) {
    $fullPath = Join-Path $RepoPath $relativePath
    Write-Host "  $relativePath" -ForegroundColor Cyan
    & snow sql `
        -c $ConnectionName `
        --role $Role `
        --database $Database `
        --schema $Schema `
        --warehouse $Warehouse `
        -f $fullPath

    if ($LASTEXITCODE -ne 0) {
        throw "Snowflake execution failed: $relativePath"
    }
}

if ($DeployApp) {
    $appScript = Join-Path $RepoPath "scripts\deploy_production_dashboard.ps1"
    if (-not (Test-Path $appScript -PathType Leaf)) {
        throw "Dashboard deployment script not found: $appScript"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $appScript `
        -RepoPath $RepoPath `
        -ConnectionName $ConnectionName `
        -Database $Database `
        -Schema $Schema `
        -Warehouse $Warehouse `
        -Role $Role `
        -AppName $AppName `
        -StageName $StageName `
        -ViewerRole $ViewerRole

    if ($LASTEXITCODE -ne 0) {
        throw "Streamlit deployment failed."
    }
}

Write-Host "Evidence impact analysis deployment completed." -ForegroundColor Green
if (-not $DeployApp) {
    Write-Host "Run again with -DeployApp to update Streamlit after committing the source." -ForegroundColor Yellow
}
