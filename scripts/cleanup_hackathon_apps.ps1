param(
    [string]$ConnectionName = "JD45494",
    [string]$Database = "READINESSOPS_VALIDATION",
    [string]$Schema = "APP",
    [string]$Role = "ACCOUNTADMIN",
    [switch]$ConfirmCleanup
)

$ErrorActionPreference = "Stop"

if (-not $ConfirmCleanup) {
    throw "Cleanup is destructive. Re-run with -ConfirmCleanup after verifying the production dashboard."
}

$tmp = Join-Path $env:TEMP "readinessops_cleanup_hackathon_apps.sql"

$sql = @"
USE ROLE $Role;
USE DATABASE $Database;
USE SCHEMA $Schema;

DROP STREAMLIT IF EXISTS $Database.$Schema.READINESSOPS_DASHBOARD_HACKATHON_DEV;
DROP STREAMLIT IF EXISTS $Database.$Schema.READINESSOPS_GOVERNANCE_REVIEW;

DROP STAGE IF EXISTS $Database.$Schema.READINESSOPS_HACKATHON_DEV_STAGE;
DROP STAGE IF EXISTS $Database.$Schema.READINESSOPS_HACKATHON_FINAL_STAGE;

SHOW STREAMLITS IN SCHEMA $Database.$Schema;
"@

[System.IO.File]::WriteAllText(
    $tmp,
    $sql,
    [System.Text.Encoding]::ASCII
)

& snow sql -c $ConnectionName -f $tmp

if ($LASTEXITCODE -ne 0) {
    throw "Cleanup failed with exit code $LASTEXITCODE"
}

Write-Host "Hackathon-only Streamlit objects removed." -ForegroundColor Green
