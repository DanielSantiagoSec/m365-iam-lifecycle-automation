# New-JoinerAccount.ps1
# HR-triggered joiner lifecycle automation via Microsoft Graph
# Simulates new employee provisioning event from HR system

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$FirstName,
    [Parameter(Mandatory)] [string]$LastName,
    [Parameter(Mandatory)] [string]$Department,
    [Parameter(Mandatory)] [string]$JobTitle
)

# --- Config ---
$TenantDomain = "danny9635live.onmicrosoft.com"
$LogFile = ".\logs\joiner_log.txt"

# --- Setup ---
if (-not (Test-Path ".\logs")) { New-Item -ItemType Directory -Path ".\logs" | Out-Null }

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

# --- Main ---
Write-Log "JOINER EVENT: $FirstName $LastName | Dept: $Department | Title: $JobTitle"

$UPN = "$($FirstName.ToLower()).$($LastName.ToLower())@$TenantDomain"
$DisplayName = "$FirstName $LastName"
$MailNickname = "$($FirstName.ToLower())$($LastName.ToLower())"
$TempPassword = "Welcome@$(Get-Random -Minimum 1000 -Maximum 9999)!"

$PasswordProfile = @{
    Password                      = $TempPassword
    ForceChangePasswordNextSignIn = $true
}

try {
    Write-Log "Creating user account: $UPN"

    $params = @{
        DisplayName       = $DisplayName
        GivenName         = $FirstName
        Surname           = $LastName
        UserPrincipalName = $UPN
        MailNickname      = $MailNickname
        Department        = $Department
        JobTitle          = $JobTitle
        AccountEnabled    = $true
        PasswordProfile   = @{
            Password                      = $TempPassword
            ForceChangePasswordNextSignIn = $true
        }
    }

    $NewUser = New-MgUser -BodyParameter $params -ErrorAction Stop

    Write-Log "SUCCESS: Account created | ObjectId: $($NewUser.Id)"
    Write-Log "Temp password issued: $TempPassword (force reset on next login)"
}
catch {
    Write-Log "ERROR: Failed to create account - $_"
    exit 1
}