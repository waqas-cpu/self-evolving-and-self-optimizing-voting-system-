$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
forge fmt --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
forge build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
forge test -vv
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
forge snapshot
exit $LASTEXITCODE
