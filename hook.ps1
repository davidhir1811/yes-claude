# Yes Claude... Hook Script (Windows)
$ErrorActionPreference = "Stop"

$ConfigFile = "$env:USERPROFILE\.yes-claude\config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Output '{"allow": false}'
    exit 0
}

$Config = Get-Content $ConfigFile | ConvertFrom-Json
$DeviceId = $Config.deviceId
$SecretToken = $Config.secretToken
$FirebaseProject = $Config.firebaseProject
$FirestoreBase = "https://firestore.googleapis.com/v1/projects/$FirebaseProject/databases/(default)/documents"

$Input = [Console]::In.ReadToEnd()

try {
    $InputObj = $Input | ConvertFrom-Json
    $Command = $InputObj.tool
    $ToolInput = $InputObj.input
    $DisplayCommand = "${Command}: ${ToolInput}"
} catch {
    $DisplayCommand = "Unknown command"
}

$RequestId = -join ((48..57) + (97..102) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$ExpiresAt = (Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$Body = @{
    fields = @{
        deviceId = @{ stringValue = $DeviceId }
        secretToken = @{ stringValue = $SecretToken }
        command = @{ stringValue = $DisplayCommand }
        choices = @{
            arrayValue = @{
                values = @(
                    @{ stringValue = "Allow" },
                    @{ stringValue = "Deny" },
                    @{ stringValue = "Allow Always" }
                )
            }
        }
        status = @{ stringValue = "pending" }
        response = @{ nullValue = $null }
        createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        expiresAt = @{ timestampValue = $ExpiresAt }
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$FirestoreBase/requests?documentId=$RequestId" -Method Post -ContentType "application/json" -Body $Body | Out-Null
} catch {
    Write-Output '{"allow": false}'
    exit 0
}

$Timeout = 300
$Elapsed = 0

while ($Elapsed -lt $Timeout) {
    try {
        $ResponseDoc = Invoke-RestMethod -Uri "$FirestoreBase/requests/$RequestId"
        $Status = $ResponseDoc.fields.status.stringValue
        if ($Status -eq "responded" -or $Status -eq "expired") {
            $Response = $ResponseDoc.fields.response.stringValue
            switch ($Response) {
                "Allow" { Write-Output '{"allow": true}'; exit 0 }
                "Allow Always" { Write-Output '{"allow": true, "always": true}'; exit 0 }
                default { Write-Output '{"allow": false}'; exit 0 }
            }
        }
    } catch {}
    Start-Sleep -Seconds 2
    $Elapsed += 2
}

Write-Output '{"allow": false}'
exit 0
