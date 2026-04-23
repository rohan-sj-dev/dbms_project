# ============================================================
#  Setup: bank_versioning_demo
#  Creates a clean demo database separate from the live
#  bank_versioning database used by the banking layer.
#
#  Run from anywhere:
#    powershell -ExecutionPolicy Bypass -File "db\demo\00_setup_demo_db.ps1"
#
#  After this script completes, open pgAdmin, connect to
#  bank_versioning_demo, and run 06_demo_walkthrough_pgadmin.sql
# ============================================================

$env:PGPASSWORD = "postgres"
$env:PGCLIENTENCODING = "UTF8"   # SQL files are UTF-8 (contain ✅ ⚠️ etc.)
$psql = "C:\Program Files\PostgreSQL\17\bin\psql.exe"
$dbDir = "$PSScriptRoot\.."   # db/ folder — so \i relative paths resolve correctly

Write-Host ""
Write-Host "============================================================"
Write-Host "  DEMO DATABASE SETUP: bank_versioning_demo"
Write-Host "============================================================"

# ---- Drop existing demo DB (clean slate) --------------------
Write-Host ""
Write-Host ">> Terminating any open connections to bank_versioning_demo..."
& $psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'bank_versioning_demo' AND pid <> pg_backend_pid();" 2>&1 | Out-Null

Write-Host ">> Dropping bank_versioning_demo (if it exists)..."
& $psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS bank_versioning_demo;" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to drop database"; exit 1 }

# ---- Create fresh demo DB -----------------------------------
Write-Host ""
Write-Host ">> Creating bank_versioning_demo..."
& $psql -U postgres -d postgres -c "CREATE DATABASE bank_versioning_demo;" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create database"; exit 1 }

# ---- Install schema, VCS, banking functions & seed data -----
Write-Host ""
Write-Host ">> Installing full schema into bank_versioning_demo..."
Write-Host "   (retail banking + VCS system + functions + views)"
Write-Host ""

# Must cd to db/ so that \i paths like vcs/01_vcs_schema.sql resolve correctly
Push-Location $dbDir
& $psql -U postgres -d bank_versioning_demo -f "00_install_all.sql" 2>&1
$exitCode = $LASTEXITCODE
Pop-Location

if ($exitCode -ne 0) { Write-Error "Installation failed (exit $exitCode)"; exit 1 }

# ---- Explicitly re-run VCS function files with absolute paths -------------
# psql \i can silently skip function definitions if a prior statement errors.
# Running the files directly ensures every VCS function is always present.
Write-Host ""
Write-Host ">> Re-applying VCS function definitions (ensuring completeness)..."
$vcsDir = Join-Path $dbDir "vcs"
foreach ($f in @("02_vcs_core_functions.sql","03_vcs_branch_functions.sql","04_vcs_history_functions.sql","05_vcs_rollback_functions.sql")) {
    & $psql -U postgres -d bank_versioning_demo -f "$vcsDir\$f" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed: $f"; exit 1 }
    Write-Host "   OK: $f"
}

# ---- Verify -------------------------------------------------
Write-Host ""
Write-Host ">> Verifying installation..."
& $psql -U postgres -d bank_versioning_demo -c "
SELECT 'Banking tables' AS category, COUNT(*) AS count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name NOT LIKE 'vcs_%'
  AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'VCS tables', COUNT(*)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE 'vcs_%'
  AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Functions', COUNT(*)
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY category;
" 2>&1

Write-Host ""
Write-Host "============================================================"
Write-Host "  DONE. Demo database is ready."
Write-Host ""
Write-Host "  In pgAdmin:"
Write-Host "    1. Expand Servers > PostgreSQL 17 > Databases"
Write-Host "    2. Connect to: bank_versioning_demo"
Write-Host "    3. Open Query Tool and run:"
Write-Host "       db\demo\06_demo_walkthrough_pgadmin.sql"
Write-Host "============================================================"
Write-Host ""
