# Yes Claude... Hook Entry Point (PowerShell)
# Dot-sources core library + CLI adapter, then runs the permission flow.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cli = if ($env:YC_CLI) { $env:YC_CLI } else { "claude" }

# Source core library
. "$ScriptDir\core.ps1"

# Source CLI adapter
$AdapterPath = "$ScriptDir\adapters\$Cli.ps1"
if (-not (Test-Path $AdapterPath)) {
    Write-Output '{"allow": false}'
    exit 0
}
. $AdapterPath

# Load config
if (-not (YC-LoadConfig)) {
    Write-Output (YC-DefaultResponse)
    exit 0
}

# Read and parse stdin
$Input = [Console]::In.ReadToEnd()
$Command = YC-ParseInput -Input $Input

# Create request
$RequestId = YC-GenerateId
try {
    YC-CreateRequest -RequestId $RequestId -Command $Command -Choices $script:YC_CHOICES -Source $script:YC_SOURCE
} catch {
    Write-Output (YC-DefaultResponse)
    exit 0
}

# Poll for response
$Response = YC-PollResponse -RequestId $RequestId
if ($Response) {
    Write-Output (YC-FormatResponse -Response $Response)
} else {
    Write-Output (YC-DefaultResponse)
}
