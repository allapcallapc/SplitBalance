<#
.SYNOPSIS
    Runs the local-Supabase integration suite (every test/integration/*.dart
    file tagged 'integration') against a real, local Postgres/PostgREST
    stack.

.DESCRIPTION
    Starts the Supabase CLI's local dev stack (Docker), resets it to a clean
    slate against supabase/migrations/*.sql, points SUPABASE_TEST_URL /
    SUPABASE_TEST_SERVICE_ROLE_KEY at it, runs `flutter test --tags
    integration`, then stops the stack (unless -KeepRunning is passed).
    This never touches the hosted/staging Supabase project or its quota -
    it's entirely local Docker containers.

.PARAMETER KeepRunning
    Skip `supabase stop` at the end, for iterating locally without paying
    the stack-startup cost on every run.

.EXAMPLE
    ./tool/run_integration_tests.ps1

.EXAMPLE
    ./tool/run_integration_tests.ps1 -KeepRunning
#>

param(
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

function Assert-CommandExists([string]$Name, [string]$InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required but wasn't found on PATH. $InstallHint"
    }
}

Assert-CommandExists 'supabase' 'Install the Supabase CLI: https://supabase.com/docs/guides/cli/getting-started'
Assert-CommandExists 'docker' 'Install Docker Desktop and make sure it is running: https://www.docker.com/products/docker-desktop/'
Assert-CommandExists 'flutter' 'Install Flutter: https://docs.flutter.dev/get-started/install'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Write-Host '==> Starting local Supabase stack (supabase start)...' -ForegroundColor Cyan
    supabase start
    if ($LASTEXITCODE -ne 0) { throw 'supabase start failed.' }

    Write-Host '==> Resetting to a clean slate against supabase/migrations/*.sql...' -ForegroundColor Cyan
    supabase db reset
    if ($LASTEXITCODE -ne 0) { throw 'supabase db reset failed.' }

    Write-Host '==> Reading local stack connection details (supabase status -o json)...' -ForegroundColor Cyan
    $statusJson = supabase status -o json | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'supabase status failed.' }
    $status = $statusJson | ConvertFrom-Json

    # Key names have shifted across CLI versions (API_URL vs api_url;
    # newer CLI versions also renamed the legacy service_role JWT to a
    # "Secret" API key - SECRET_KEY/secret_key) - try all variants.
    $apiUrl = $status.API_URL
    if (-not $apiUrl) { $apiUrl = $status.api_url }
    $serviceRoleKey = $status.SERVICE_ROLE_KEY
    if (-not $serviceRoleKey) { $serviceRoleKey = $status.service_role_key }
    if (-not $serviceRoleKey) { $serviceRoleKey = $status.SECRET_KEY }
    if (-not $serviceRoleKey) { $serviceRoleKey = $status.secret_key }

    if (-not $apiUrl -or -not $serviceRoleKey) {
        Write-Host 'Raw `supabase status -o json` output for debugging:' -ForegroundColor Yellow
        Write-Host $statusJson
        throw 'Could not find API URL / service role key in `supabase status -o json` output - the field names may have changed in your CLI version. See the raw output above and adjust this script.'
    }

    $env:SUPABASE_TEST_URL = $apiUrl
    $env:SUPABASE_TEST_SERVICE_ROLE_KEY = $serviceRoleKey

    Write-Host "==> Running integration tests against $apiUrl ..." -ForegroundColor Cyan
    flutter test --tags integration --run-skipped
    $testExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:\SUPABASE_TEST_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\SUPABASE_TEST_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue

    if (-not $KeepRunning) {
        Write-Host '==> Stopping local Supabase stack...' -ForegroundColor Cyan
        supabase stop
    }
    else {
        Write-Host '==> Leaving the local Supabase stack running (-KeepRunning).' -ForegroundColor Cyan
    }

    Pop-Location
}

if ($testExitCode -ne 0) {
    exit $testExitCode
}
