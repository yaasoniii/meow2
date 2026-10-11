# Compiles every Ballerina service (no Docker needed). Usage: .\build.ps1 [service-folder ...]
param([string[]]$Services = @("order-service", "customer-service", "restaurant-service", "payment-service",
        "delivery-service", "notification-service", "admin-service"))

$bal = (Get-Command bal -ErrorAction SilentlyContinue).Source
if (-not $bal) { $bal = "C:\Program Files\Ballerina\bin\bal.bat" }

$failed = @()
foreach ($svc in $Services) {
    Write-Host "=== $svc" -ForegroundColor Cyan
    Push-Location (Join-Path $PSScriptRoot $svc)
    # bal.bat doesn't reliably propagate its exit code, so also look for the error line.
    $out = & $bal build 2>&1 | ForEach-Object { "$_" }
    $out | Where-Object { $_ -notmatch 'pulled from central|\d+% \[' } | Write-Host
    if ($LASTEXITCODE -ne 0 -or ($out -match '^error:')) { $failed += $svc }
    Pop-Location
}
if ($failed.Count -gt 0) { Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All services built." -ForegroundColor Green
