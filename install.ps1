# Yes Claude... Installer for Windows
# Usage: irm https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$InstallDir = "$env:USERPROFILE\.yes-claude"
$HookUrl = "https://raw.githubusercontent.com/davidhir1811/yes-claude/main/hook.ps1"
$FirebaseProject = "yes-claude-XXXXX"
$FirestoreBase = "https://firestore.googleapis.com/v1/projects/$FirebaseProject/databases/(default)/documents"

Write-Host "==================================="
Write-Host "  Yes Claude... Installer"
Write-Host "==================================="
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "Downloading hook script..."
Invoke-RestMethod -Uri $HookUrl -OutFile "$InstallDir\hook.ps1"

$PairingCode = -join ((65..90) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$SecretToken = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

Write-Host "Registering device..."
$Body = @{
    fields = @{
        secretToken = @{ stringValue = $SecretToken }
        fcmToken = @{ stringValue = "" }
        createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        pairedAt = @{ nullValue = $null }
    }
} | ConvertTo-Json -Depth 5

try {
    Invoke-RestMethod -Uri "$FirestoreBase/devices?documentId=$PairingCode" -Method Post -ContentType "application/json" -Body $Body | Out-Null
} catch {
    Write-Host "ERROR: Failed to register device."
    Write-Host $_.Exception.Message
    exit 1
}

Write-Host ""
Write-Host "==================================="
Write-Host "  Enter this code in the app:"
Write-Host ""
Write-Host "        $PairingCode"
Write-Host ""
Write-Host "==================================="
Write-Host ""
Write-Host "Waiting for pairing..."

$Timeout = 600
$Elapsed = 0
$Paired = $false

while ($Elapsed -lt $Timeout) {
    try {
        $DeviceDoc = Invoke-RestMethod -Uri "$FirestoreBase/devices/$PairingCode"
        $FcmToken = $DeviceDoc.fields.fcmToken.stringValue
        if ($FcmToken -and $FcmToken -ne "") {
            Write-Host "Paired successfully!"
            $Paired = $true
            break
        }
    } catch {}
    Start-Sleep -Seconds 2
    $Elapsed += 2
}

if (-not $Paired) {
    Write-Host "ERROR: Pairing timed out after 10 minutes."
    exit 1
}

$Config = @{
    deviceId = $PairingCode
    secretToken = $SecretToken
    firebaseProject = $FirebaseProject
} | ConvertTo-Json
Set-Content -Path "$InstallDir\config.json" -Value $Config

$ClaudeSettings = "$env:USERPROFILE\.claude\settings.json"
$ClaudeDir = Split-Path $ClaudeSettings
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
}

$HookEntry = @{
    type = "command"
    command = "powershell -File `"$InstallDir\hook.ps1`""
}

if (Test-Path $ClaudeSettings) {
    $Settings = Get-Content $ClaudeSettings | ConvertFrom-Json
    if (-not $Settings.hooks) {
        $Settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
    }
    if (-not $Settings.hooks.permissionPrompt) {
        $Settings.hooks | Add-Member -NotePropertyName "permissionPrompt" -NotePropertyValue @()
    }
    $Existing = $Settings.hooks.permissionPrompt | Where-Object { $_.command -like "*yes-claude*" }
    if (-not $Existing) {
        $Settings.hooks.permissionPrompt += $HookEntry
    }
    $Settings | ConvertTo-Json -Depth 10 | Set-Content $ClaudeSettings
} else {
    @{
        hooks = @{
            permissionPrompt = @($HookEntry)
        }
    } | ConvertTo-Json -Depth 10 | Set-Content $ClaudeSettings
}

Write-Host ""
Write-Host "Installation complete!"
Write-Host "Config: $InstallDir\config.json"
Write-Host "Hook: $InstallDir\hook.ps1"
