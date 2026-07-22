param(
    [string]$ConnectionName = "JD45494",
    [string]$Database = "READINESSOPS_VALIDATION",
    [string]$Schema = "APP",
    [string]$Warehouse = "READINESSOPS_WH",
    [string]$Role = "ACCOUNTADMIN",
    [string]$AppName = "READINESSOPS_DASHBOARD",
    [string]$LegacyStageName = "STREAMLIT_STAGE"
)

$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP "readinessops_rollback_production.sql"

$sql = @"
USE ROLE $Role;
USE DATABASE $Database;
USE SCHEMA $Schema;
USE WAREHOUSE $Warehouse;

CREATE OR REPLACE STREAMLIT $Database.$Schema.$AppName
  ROOT_LOCATION = '@$Database.$Schema.$LegacyStageName'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = $Warehouse
  TITLE = 'ReadinessOps'
  COMMENT = 'Restored from the preserved legacy Streamlit stage.';

DESC STREAMLIT $Database.$Schema.$AppName;
"@

[System.IO.File]::WriteAllText(
    $tmp,
    $sql,
    [System.Text.Encoding]::ASCII
)

& snow sql -c $ConnectionName -f $tmp

if ($LASTEXITCODE -ne 0) {
    throw "Production rollback failed with exit code $LASTEXITCODE"
}

Write-Host "Production dashboard restored from $LegacyStageName." -ForegroundColor Green
