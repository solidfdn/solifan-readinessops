param(
    [string]$ConnectionName = "JD45494"
)

$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP "readinessops_rollback_production.sql"
$sql = @'
USE ROLE ACCOUNTADMIN;
USE DATABASE READINESSOPS_VALIDATION;
USE SCHEMA APP;
USE WAREHOUSE READINESSOPS_WH;

-- Restore the previously working legacy stage.
CREATE OR REPLACE STREAMLIT
    READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD
    ROOT_LOCATION =
        '@READINESSOPS_VALIDATION.APP.STREAMLIT_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = READINESSOPS_WH
    TITLE = 'ReadinessOps'
    COMMENT = 'Rolled back to the preserved legacy deployment.';

DESC STREAMLIT READINESSOPS_VALIDATION.APP.READINESSOPS_DASHBOARD;
'@

[System.IO.File]::WriteAllText(
    $tmp,
    $sql,
    [System.Text.Encoding]::ASCII
)

& snow sql -c $ConnectionName -f $tmp
if ($LASTEXITCODE -ne 0) {
    throw "Production rollback failed with exit code $LASTEXITCODE"
}

Write-Host "Production dashboard restored to the preserved legacy stage." -ForegroundColor Green
