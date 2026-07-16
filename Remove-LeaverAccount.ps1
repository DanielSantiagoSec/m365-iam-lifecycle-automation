# Remove-LeaverAccount.ps1
# HR-triggered leaver lifecycle automation via Microsoft Graph
# Simulates offboarding event from HR system

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$UserPrincipalName
)

$LogFile = ".\logs\leaver_log.txt"

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "LEAVER EVENT: $UserPrincipalName"

try {
    $User = Get-MgUser -UserId $UserPrincipalName -Property "Id,DisplayName,Department,JobTitle,AccountEnabled" -ErrorAction Stop
    Write-Log "Found user: $($User.DisplayName) | Dept: $($User.Department) | Title: $($User.JobTitle)"

    # Step 1 - Disable account
    Update-MgUser -UserId $User.Id -BodyParameter @{ AccountEnabled = $false } -ErrorAction Stop
    Write-Log "STEP 1 SUCCESS: Account disabled"

    # Step 2 - Revoke all active sessions
    Revoke-MgUserSignInSession -UserId $User.Id -ErrorAction Stop
    Write-Log "STEP 2 SUCCESS: All active sessions revoked"

    # Step 3 - Remove group memberships
    $Groups = Get-MgUserMemberOf -UserId $User.Id -ErrorAction Stop
    foreach ($Group in $Groups) {
        try {
            Remove-MgGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
            Write-Log "STEP 3: Removed from group $($Group.Id)"
        }
        catch {
            Write-Log "STEP 3 NOTE: Could not remove from group $($Group.Id) - $_"
        }
    }

    Write-Log "LEAVER COMPLETE: $($User.DisplayName) fully offboarded"
}
catch {
    Write-Log "ERROR: Leaver process failed - $_"
    exit 1
}