param(
    [string]$ConnectionName = "JD45494"
)

$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP "readinessops_cleanup_hackathon_apps.sql"
$sql = @'
USE ROLE ACCOUNTADMIN;
USE DATABASE READINESSOPS_VALIDATION;
USE SCHEMA APP;

-- Run only after READINESSOPS_DASHBOARD has been verified.
DROP STREAMLIT IF EXISTS
    READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD_HACKATHON_DEV;

DROP STREAMLIT IF EXISTS
    READINESSOPS_VALIDATION.APP.READINESSOPS_GOVERNANCE_REVIEW;

DROP STAGE IF EXISTS
    READINESSOPS_VALIDATION.APP.READINESSOPS_HACKATHON_DEV_STAGE;

DROP STAGE IF EXISTS
    READINESSOPS_VALIDATION.APP.READINESSOPS_HACKATHON_FINAL_STAGE;

SHOW STREAMLITS IN SCHEMA READINESSOPS_VALIDATION.APP;
'@

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
