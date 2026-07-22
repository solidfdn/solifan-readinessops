param(
    [string]$RepoPath = "C:\Users\okada\Documents\READINESSOPS",
    [string]$ConnectionName = "JD45494"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $RepoPath)) {
    throw "Repository not found: $RepoPath"
}

$SourceApp = Join-Path $RepoPath "app\streamlit_app.py"
if (-not (Test-Path $SourceApp)) {
    throw "Canonical Streamlit source not found: $SourceApp"
}

$AuditDir = Join-Path $RepoPath "_audit"
New-Item $AuditDir -ItemType Directory -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$SqlFile = Join-Path $AuditDir "deploy_production_dashboard_$stamp.sql"
$putPath = $SourceApp.Replace("\", "/")

$sql = @"
USE ROLE ACCOUNTADMIN;
USE DATABASE READINESSOPS_VALIDATION;
USE SCHEMA APP;
USE WAREHOUSE READINESSOPS_WH;

-- Keep the old STREAMLIT_STAGE intact for immediate rollback.
CREATE STAGE IF NOT EXISTS
    READINESSOPS_VALIDATION.APP.READINESSOPS_PRODUCTION_STAGE;

REMOVE
    @READINESSOPS_VALIDATION.APP.READINESSOPS_PRODUCTION_STAGE
    PATTERN='.*';

PUT 'file://$putPath'
    @READINESSOPS_VALIDATION.APP.READINESSOPS_PRODUCTION_STAGE
    AUTO_COMPRESS = FALSE
    OVERWRITE = TRUE;

CREATE OR REPLACE STREAMLIT
    READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD
    ROOT_LOCATION =
        '@READINESSOPS_VALIDATION.APP.READINESSOPS_PRODUCTION_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = READINESSOPS_WH
    TITLE = 'ReadinessOps Governance Review'
    COMMENT =
        'Production ReadinessOps governance review: Evidence, AI proposal, human decision, publication, and audit traceability.';

DESC STREAMLIT READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD;
"@

[System.IO.File]::WriteAllText(
    $SqlFile,
    $sql,
    [System.Text.Encoding]::ASCII
)

Write-Host "Deploying canonical Git source to READINESSOPS_DASHBOARD..." -ForegroundColor Cyan
& snow sql -c $ConnectionName -f $SqlFile

if ($LASTEXITCODE -ne 0) {
    throw "Production deployment failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Production dashboard updated." -ForegroundColor Green
Write-Host "Open:" -ForegroundColor Cyan
Write-Host "https://app.snowflake.com/KBXRZUR/jd45494/#/streamlit-apps/READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD" -ForegroundColor Yellow
