# Yes Claude... Core Hook Library (PowerShell)
# Shared Firestore API, polling, and config loading.
# Dot-sourced by hooks/hook.ps1 — do not run directly.

function YC-LoadConfig {
    $configFile = "$env:USERPROFILE\.yes-claude\config.json"
    if (-not (Test-Path $configFile)) { return $false }

    $config = Get-Content $configFile | ConvertFrom-Json
    $script:YC_DEVICE_ID = $config.deviceId
    $script:YC_SECRET_TOKEN = $config.secretToken
    $script:YC_FIREBASE_PROJECT = $config.firebaseProject
    $script:YC_FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/$($config.firebaseProject)/databases/(default)/documents"

    if (-not $script:YC_DEVICE_ID -or -not $script:YC_SECRET_TOKEN) { return $false }
    return $true
}

function YC-CreateRequest {
    param(
        [string]$RequestId,
        [string]$Command,
        [array]$Choices,
        [string]$Source,
        [string]$SessionLabel = (Split-Path -Leaf (Get-Location)),
        [string]$MachineId = $env:COMPUTERNAME
    )

    $expiresAt = (Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $choicesValues = $Choices | ForEach-Object { @{ stringValue = $_ } }

    $body = @{
        fields = @{
            deviceId = @{ stringValue = $script:YC_DEVICE_ID }
            secretToken = @{ stringValue = $script:YC_SECRET_TOKEN }
            command = @{ stringValue = $Command }
            choices = @{ arrayValue = @{ values = @($choicesValues) } }
            status = @{ stringValue = "pending" }
            response = @{ nullValue = $null }
            sessionLabel = @{ stringValue = $SessionLabel }
            machineId = @{ stringValue = $MachineId }
            source = @{ stringValue = $Source }
            createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
            expiresAt = @{ timestampValue = $expiresAt }
        }
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri "$($script:YC_FIRESTORE_BASE)/requests?documentId=$RequestId" -Method Post -ContentType "application/json" -Body $body | Out-Null
}

function YC-PollResponse {
    param(
        [string]$RequestId,
        [int]$Timeout = 300
    )

    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        try {
            $doc = Invoke-RestMethod -Uri "$($script:YC_FIRESTORE_BASE)/requests/$RequestId"
            $status = $doc.fields.status.stringValue
            if ($status -eq "responded" -or $status -eq "expired") {
                return $doc.fields.response.stringValue
            }
        } catch {}
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    return $null
}

function YC-GenerateId {
    -join ((48..57) + (97..102) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
}
