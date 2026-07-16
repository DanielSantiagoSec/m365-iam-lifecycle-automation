# Set-MoverAccount.ps1
# HR-triggered mover lifecycle automation via Microsoft Graph
# Simulates internal transfer event from HR system

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$UserPrincipalName,
    [Parameter(Mandatory)] [string]$NewDepartment,
    [Parameter(Mandatory)] [string]$NewJobTitle
)

$LogFile = ".\logs\mover_log.txt"

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "MOVER EVENT: $UserPrincipalName | New Dept: $NewDepartment | New Title: $NewJobTitle"

try {
    $User = Get-MgUser -UserId $UserPrincipalName -Property "Id,DisplayName,Department,JobTitle" -ErrorAction Stop
    Write-Log "Found user: $($User.DisplayName) | Current Dept: $($User.Department) | Current Title: $($User.JobTitle)"

    $params = @{
        Department = $NewDepartment
        JobTitle   = $NewJobTitle
    }

    Update-MgUser -UserId $User.Id -BodyParameter $params -ErrorAction Stop

    Write-Log "SUCCESS: Profile updated | Dept: $NewDepartment | Title: $NewJobTitle"
}
catch {
    Write-Log "ERROR: Mover update failed - $_"
    exit 1
}