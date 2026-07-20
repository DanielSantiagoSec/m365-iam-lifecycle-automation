# Permission Model Design — M365 IAM Lifecycle Automation

> **Why this document exists:** Anyone can assign a role. This document explains the reasoning behind every permission decision in this lab — the security principle it maps to, what was considered and rejected, and what the residual risk is. That's the difference between configuration and design.

---

## Overview

This lab automates the joiner/mover/leaver (JML) identity lifecycle using Microsoft Graph PowerShell. Three scripts handle the three lifecycle events:

| Script | Event | Action |
|---|---|---|
| `New-JoinerAccount.ps1` | Joiner | Provision user, assign licenses, add to groups, enable account |
| `Set-MoverAccount.ps1` | Mover | Update attributes, adjust group membership, reassign licenses |
| `Remove-LeaverAccount.ps1` | Leaver | Disable account, revoke sessions, remove licenses, offboard |

Each script runs under a **dedicated service principal** scoped to the minimum permissions required for its function. No script shares credentials or permission scope with another.

---

## Core Design Principles

### 1. Least Privilege
No identity — human or non-human — holds more permission than required to complete its specific task. This is not just a best practice; it's the primary control that limits blast radius if a service principal is compromised.

### 2. Separation of Duties
Joiner, Mover, and Leaver operations run under separate service principals. A compromised Joiner service principal cannot disable accounts. A compromised Leaver service principal cannot provision new users. This is an intentional architectural decision, not a convenience.

### 3. Non-Human Identity Governance
Service principals are identities too. Each one has an owner, a documented purpose, an expiration policy on its credentials, and a defined review cadence. Undocumented service principals with broad permissions are one of the most common causes of M365 tenant compromise.

### 4. Audit by Default
Every operation writes to a structured audit log before and after execution. The log captures who ran the script, what changed, and when. This is not optional — it's a design requirement. You cannot govern what you cannot see.

---

## Service Principal Design

### SP-1: `svc-iam-joiner`

**Purpose:** Provisions new user accounts during the onboarding lifecycle event.

**Microsoft Graph API Permissions (Application):**

| Permission | Scope | Justification | Rejected Alternative |
|---|---|---|---|
| `User.ReadWrite.All` | Application | Required to create user objects and set all attributes on provisioning | `User.Read.All` — read-only, insufficient for creation |
| `Group.ReadWrite.All` | Application | Required to add new users to their assigned security/M365 groups | `Group.Read.All` — cannot modify membership |
| `Directory.ReadWrite.All` | ❌ Rejected | — | Too broad — grants control over the entire directory including privileged objects |
| `LicenseAssignment` (via `User.ReadWrite.All`) | Inherited | License assignment is covered under `User.ReadWrite.All` scope in Graph | Separate license SP was considered but added complexity without meaningful security gain at this lab scale |

**What this SP cannot do:**
- Disable or delete accounts
- Modify existing users (mover operations)
- Read or modify conditional access policies
- Assign admin roles to users
- Access privileged identity management (PIM)

**Credential policy:** Client secret, 90-day rotation, stored in environment variable (not hardcoded). In production: Azure Key Vault reference.

---

### SP-2: `svc-iam-mover`

**Purpose:** Handles attribute updates and group membership changes when a user changes role, department, or location.

**Microsoft Graph API Permissions (Application):**

| Permission | Scope | Justification | Rejected Alternative |
|---|---|---|---|
| `User.ReadWrite.All` | Application | Required to update user attributes (department, jobTitle, manager, UPN changes) | `User.Read.All` — read-only |
| `Group.ReadWrite.All` | Application | Required to remove from old groups and add to new groups on role change | None viable at this scope |
| `Mail.ReadWrite` | ❌ Rejected | — | Not required for lifecycle automation; would grant access to mailbox content |

**What this SP cannot do:**
- Create new user accounts
- Disable or delete accounts
- Assign or remove licenses independently (license changes during a move are handled by calling the Joiner or Leaver SP workflow, not by this SP directly)

**Design note on license management during moves:** This was a deliberate tradeoff. Giving the Mover SP license assignment capability would simplify the code but violates separation of duties — a mover operation shouldn't also be able to provision new entitlements. In this lab, license changes during a role change trigger a documented manual approval step, which mirrors real enterprise JML governance workflows.

---

### SP-3: `svc-iam-leaver`

**Purpose:** Executes offboarding — disabling accounts, revoking active sessions, removing licenses, and removing group memberships.

**Microsoft Graph API Permissions (Application):**

| Permission | Scope | Justification | Rejected Alternative |
|---|---|---|---|
| `User.ReadWrite.All` | Application | Required to disable account (`accountEnabled: false`) and clear attributes | Scoped user permissions don't exist at the application level in Graph for targeted disable operations |
| `Group.ReadWrite.All` | Application | Required to remove the departing user from all group memberships | `Group.Read.All` — cannot modify |
| `Directory.AccessAsUser.All` | ❌ Rejected | — | Delegated permission only; would require interactive login, incompatible with automation |
| Session revocation via `revokeSignInSessions` | Covered under `User.ReadWrite.All` | Graph's `revokeSignInSessions` action is available under this scope | No separate permission required |

**What this SP cannot do:**
- Hard-delete user objects (permanent deletion requires `Directory.ReadWrite.All` — intentionally excluded; soft-delete + 30-day retention is the enforced model)
- Create or modify accounts
- Access mailbox content

**Design note on hard delete:** Hard deletion was explicitly excluded from this SP's scope. Soft-delete with a 30-day retention window is the enforced offboarding posture. This preserves the ability to recover an accidentally offboarded account without a ticket to Microsoft Support and aligns with most enterprise data retention policies. Hard delete, if ever required, should be a separate, manually approved, break-glass operation — not an automated script.

---

## Audit Log Design

Every script writes a structured log entry to `./logs/audit-<date>.csv` with the following schema:

```
Timestamp | RunBy | ScriptName | TargetUPN | Action | Status | Notes
```

**Why CSV and not a SIEM integration?** At lab scale, CSV is portable, reviewable without tooling, and demonstrable in an interview. In a production environment, these logs would ship to Microsoft Sentinel via a Log Analytics workspace, enabling KQL-based alerting on anomalous provisioning patterns (e.g., accounts created outside business hours, mass-offboarding events).

**What the audit log proves:** That every lifecycle change is attributable, timestamped, and reviewable. This satisfies the basic requirement of any identity governance audit and is the foundation for access certification workflows.

---

## What's Out of Scope (and Why)

| Capability | Decision | Reasoning |
|---|---|---|
| Privileged Role Assignment (GA, Security Admin) | Out of scope | Privileged role assignment requires `RoleManagement.ReadWrite.Directory` — a high-risk permission that should never be automated without PIM integration and approval workflow |
| Conditional Access policy management | Out of scope | CA policy changes are a security-critical operation requiring change management, not lifecycle automation |
| Manager approval workflow | Documented gap | In production, joiner/mover events should require manager approval before execution. This lab simulates that with a `$ApprovalRequired` flag but does not integrate with a ticketing system |
| PIM just-in-time access | Future state | The natural next layer — privileged access should be time-bound and require justification, not permanently assigned |

---

## Threat Model: What Happens if a Service Principal Is Compromised?

| SP Compromised | Attacker Can | Attacker Cannot |
|---|---|---|
| `svc-iam-joiner` | Create rogue user accounts, add them to non-privileged groups | Disable existing accounts, assign admin roles, access existing user data |
| `svc-iam-mover` | Modify user attributes, change group memberships | Create accounts, disable accounts, assign licenses |
| `svc-iam-leaver` | Disable user accounts (DoS risk), revoke sessions, remove group memberships | Create accounts, assign privileges, access mailbox content |

**Highest risk:** `svc-iam-leaver` compromise is the most operationally disruptive — an attacker could mass-disable accounts. Mitigation: alert on bulk `accountEnabled: false` operations (>5 in 10 minutes) in Sentinel or Defender for Identity.

---

## References

- [Microsoft Graph Permissions Reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft Identity Platform: Least Privilege Best Practices](https://learn.microsoft.com/en-us/entra/identity-platform/secure-least-privileged-access)
- [NIST SP 800-63B: Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- [Entra ID: Service Principal Security Best Practices](https://learn.microsoft.com/en-us/entra/architecture/secure-service-accounts-introduction)
