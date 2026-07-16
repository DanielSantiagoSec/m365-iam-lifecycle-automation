# M365 IAM Lifecycle Automation

Graph PowerShell scripts automating HR-triggered joiner/mover/leaver 
identity lifecycle events in Microsoft Entra ID.

## Overview

Simulates the identity lifecycle workflows triggered by HR system events 
in an enterprise IAM environment. Each script represents a discrete 
lifecycle stage and produces a timestamped audit log.

## Scripts

| Script | Lifecycle Event | Trigger |
|--------|----------------|---------|
| `New-JoinerAccount.ps1` | New hire provisioning | HR new employee event |
| `Set-MoverAccount.ps1` | Internal transfer update | HR department/title change |
| `Remove-LeaverAccount.ps1` | Offboarding | HR termination event |

## What Each Script Does

### Joiner
- Creates Entra ID user account with UPN derived from HR data
- Sets department, job title, and display name from HR payload
- Issues temporary password with forced reset on first login
- Logs ObjectId for audit trail

### Mover
- Looks up existing user by UPN
- Updates department and job title to reflect new role
- Logs before/after state for change record

### Leaver
- Disables account immediately
- Revokes all active sessions
- Removes group memberships
- Produces complete offboarding audit log

## Usage

```powershell
# Joiner
.\New-JoinerAccount.ps1 -FirstName "Jane" -LastName "Doe" `
  -Department "IT Security" -JobTitle "Security Analyst"

# Mover
.\Set-MoverAccount.ps1 -UserPrincipalName "jane.doe@tenant.onmicrosoft.com" `
  -NewDepartment "Threat Intelligence" -NewJobTitle "Senior Security Analyst"

# Leaver
.\Remove-LeaverAccount.ps1 -UserPrincipalName "jane.doe@tenant.onmicrosoft.com"
```

## Environment

Tested against Microsoft Entra ID using Microsoft.Graph PowerShell SDK v2.38.1.
Lab environment: Azure free tier tenant.
