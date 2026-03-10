# Yes Claude... Claude Code Adapter (PowerShell)
# Parses Claude Code's hook stdin and formats responses.
# Dot-sourced by hooks/hook.ps1 — do not run directly.

$script:YC_SOURCE = "claude"
$script:YC_CHOICES = @("Allow", "Deny", "Allow Always")

function YC-ParseInput {
    param([string]$Input)

    try {
        $obj = $Input | ConvertFrom-Json
        $command = $obj.tool
        $toolInput = $obj.input
        return "${command}: ${toolInput}"
    } catch {
        return "Unknown command"
    }
}

function YC-FormatResponse {
    param([string]$Response)

    switch ($Response) {
        "Allow" { return '{"allow": true}' }
        "Allow Always" { return '{"allow": true, "always": true}' }
        default { return '{"allow": false}' }
    }
}

function YC-DefaultResponse {
    return '{"allow": false}'
}
