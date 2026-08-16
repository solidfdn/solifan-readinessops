param(
    [string]$RepoPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ConnectionName = "JD45494",
    [string]$Database = "READINESSOPS_VALIDATION",
    [string]$Schema = "APP",
    [string]$Warehouse = "READINESSOPS_WH",
    [string]$Role = "ACCOUNTADMIN",
    [string]$AppName = "READINESSOPS_DASHBOARD",
    [string]$StageName = "READINESSOPS_PRODUCTION_STAGE"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    throw "Git repository not found: $RepoPath"
}

$SourceApp = Join-Path $RepoPath "app\streamlit_app.py"
$SourceModule = Join-Path $RepoPath "app\value_control_plane.py"
if (-not (Test-Path $SourceApp)) {
    throw "Canonical Streamlit source not found: $SourceApp"
}
if (-not (Test-Path $SourceModule)) {
    throw "Value Control Plane module not found: $SourceModule"
}

$status = & git -C $RepoPath status --porcelain
if ($status) {
    throw "Working tree is not clean. Deploy only a committed Git state."
}

$AuditDir = Join-Path $RepoPath "_audit"
New-Item $AuditDir -ItemType Directory -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SqlFile = Join-Path $AuditDir "deploy_production_dashboard_$stamp.sql"
$putPath = $SourceApp.Replace("\", "/")
$modulePutPath = $SourceModule.Replace("\", "/")

$sql = @"
USE ROLE $Role;
USE DATABASE $Database;
USE SCHEMA $Schema;
USE WAREHOUSE $Warehouse;

CREATE STAGE IF NOT EXISTS $Database.$Schema.$StageName;

-- Upload the dependency first so the currently deployed app remains runnable
-- if either PUT fails. Existing stage files are overwritten by exact name.
PUT 'file://$modulePutPath'
  @$Database.$Schema.$StageName
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;

PUT 'file://$putPath'
  @$Database.$Schema.$StageName
  AUTO_COMPRESS = FALSE
  OVERWRITE = TRUE;

CREATE OR REPLACE STREAMLIT $Database.$Schema.$AppName
  ROOT_LOCATION = '@$Database.$Schema.$StageName'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = $Warehouse
  TITLE = 'ReadinessOps Governance Review'
  COMMENT = 'Evidence, AI proposal, human decision, controlled publication, and audit traceability.';

DESC STREAMLIT $Database.$Schema.$AppName;
"@

[System.IO.File]::WriteAllText(
    $SqlFile,
    $sql,
    [System.Text.Encoding]::ASCII
)

Write-Host "Deploying committed Streamlit source..." -ForegroundColor Cyan
& snow sql -c $ConnectionName -f $SqlFile

if ($LASTEXITCODE -ne 0) {
    throw "Production deployment failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Production dashboard updated." -ForegroundColor Green
Write-Host "Object: $Database.$Schema.$AppName" -ForegroundColor Cyan
Write-Host "Open the object from Snowsight > Streamlit." -ForegroundColor Yellow
