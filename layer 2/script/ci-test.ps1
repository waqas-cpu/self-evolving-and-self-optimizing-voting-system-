$ErrorActionPreference = "Stop"
forge fmt --check
forge build
forge test -vv
forge snapshot
