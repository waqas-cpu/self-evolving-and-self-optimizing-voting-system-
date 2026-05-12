$ErrorActionPreference = "Stop"

Write-Host "==> Formatting check"
forge fmt --check

Write-Host "==> Build"
forge build

Write-Host "==> Unit and property tests"
forge test -vv

Write-Host "==> Gas snapshot"
forge snapshot
