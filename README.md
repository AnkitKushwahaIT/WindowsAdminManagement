# WindowsAdminManagement

Remove directly assigned Microsoft Entra users from the local **Administrators** group on Windows devices. Deploy as a Microsoft Intune Win32 app with a cleanup installer and live membership detection. Optional Intune Remediations are also supported.

> [!WARNING]
> **⚠️ AI-assisted code — review before execution**
>
> Parts of these scripts were generated with AI assistance.
>
> - 🔍 Read and review the complete scripts carefully and understand the changes they make.
> - 🛠️ Adapt them to your organization's requirements before executing them in your environment.
> - 🧪 Test on a non-production device first.
> - 🔐 Verify that an emergency administrator account remains available before production deployment.

## What it does

The default policy removes members whose names begin with `AzureAD\` and whose object class is `User`. Exact SID exclusions let organizations retain approved Entra users.

| Member | Default behavior |
| --- | --- |
| Direct `AzureAD\user` entry classified as User | Remove |
| User SID listed in `ExcludedMemberSids` | Keep |
| Local accounts, including Windows LAPS accounts | Keep |
| Domain accounts and groups | Keep |
| Entra groups, role entries and unresolved SID entries | Keep |

This is **direct Entra user membership cleanup**, not an "only one administrator" policy. It does not guarantee that a user has no effective administrative privileges through other groups or Entra roles. It does not create users, change passwords, disable accounts, change logon rights, or configure LAPS.

## Requirements

- Windows endpoints with the Microsoft.PowerShell.LocalAccounts module.
- Elevated **64-bit Windows PowerShell 5.1** on 64-bit Windows, or SYSTEM context.
- An independently verified recovery administrator before removing access.

Administrators is addressed by SID, so the script does not depend on the Windows display language. If membership enumeration fails, the script reports an error instead of assuming compliance. Unresolved entries that can be enumerated are retained; there is no orphaned-SID removal fallback.

## Quick start

Open elevated Windows PowerShell in the repository root.

```powershell
# Preview without account or log-file changes.
.\scripts\Invoke-LocalAdminCleanup.ps1 -WhatIf

# Apply the default policy.
.\scripts\Invoke-LocalAdminCleanup.ps1

# Read-only check of the resulting membership.
.\scripts\Detect-LocalAdminCleanup.ps1
```

### Retain selected Entra users

Find the exact SID in the local membership inventory:

```powershell
Get-LocalGroupMember -SID 'S-1-5-32-544' |
    Select-Object Name, ObjectClass, PrincipalSource, SID
```

Pass the same exclusions to both scripts. Replace this illustrative SID with a verified user SID:

```powershell
$excluded = @('S-1-12-1-111-222-333-444')
.\scripts\Invoke-LocalAdminCleanup.ps1 -ExcludedMemberSids $excluded -WhatIf
.\scripts\Invoke-LocalAdminCleanup.ps1 -ExcludedMemberSids $excluded
.\scripts\Detect-LocalAdminCleanup.ps1 -ExcludedMemberSids $excluded
```

For Intune uploads, set identical `ExcludedMemberSids` defaults in your deployment copies of both scripts. Keep organization-specific configuration out of public contributions.

### Logs and exit codes

Cleanup logs to `%ProgramData%\WindowsAdminManagement\LocalAdminCleanup.log`. Override with `-LogFolder 'C:\CompanyIT\Logs'`. Detailed identifiers stay in the local log; normal status output contains counts. Errors can include identifiers from Windows error messages. Preview displays target identities in the console.

| Script | Exit code | Meaning |
| --- | --- | --- |
| Detection | 0 | No targeted members |
| Detection (Win32 default) | 1 | Targeted members found or unable to evaluate; not detected |
| Detection (Remediation mode) | 1 / 2 | Targeted members / evaluation error |
| Cleanup | 0 | Verified cleanup success, or completed WhatIf preview |
| Cleanup | 1 | Preflight, removal, verification or logging failure |

Preview exit 0 does not indicate compliance. Cleanup verifies live membership after removal. No completion marker is used: a historical marker cannot establish current membership.

## Intune Win32 app

Package `Invoke-LocalAdminCleanup.ps1` as the installer and upload `Detect-LocalAdminCleanup.ps1` as the custom detection rule. Assign as **Required** to your pilot device group and run the installer as **System** in 64-bit PowerShell.

Detection uses `AzureAD\` plus `ObjectClass = User`, not an email-domain match. Local names do not necessarily contain a user's UPN or company email domain.

- No targeted users: exit 0 with stdout; Intune detects the desired state and skips installation.
- Targeted users: exit 1; the required app is not detected and cleanup can run.
- Detection error: exit 1 with an error message; investigate the error. Cleanup independently rechecks membership before changing it.
- After cleanup: Intune evaluates membership again. No completion file is required.

See the [Win32 packaging and deployment guide](docs/Intune-Deployment.md) for exact commands, custom detection settings, troubleshooting and pilot acceptance criteria. Optional Remediations require `DeploymentType = 'Remediation'` in the uploaded detection copy to retain a distinct error exit code.

## Deployment and maintenance

- [Intune deployment](docs/Intune-Deployment.md)
- [Security, scope and recovery](docs/Security-Guidance.md)
- [Contributing](CONTRIBUTING.md)

Existing deployments of older versions must replace both scripts and their detection rules. The earlier account-creation scripts and broad administrator allowlist policy have been retired. This version preserves all local accounts by design; it does not reset their passwords. Existing completion-marker files are ignored and are not automatically deleted. Do not continue using marker-only detection with this version.

## Testing

Run the isolated behavioral checks on Windows:

```powershell
powershell.exe -NoProfile -File .\tests\Test-LocalAdminCleanup.ps1
```

The tests mock account management and logging commands; they do not modify Windows accounts. A Windows CI workflow runs the same checks. These checks are not a substitute for a managed-device pilot, including your actual LAPS recovery and Entra role configuration.

## License

[The Unlicense](LICENSE). Review and adapt the scripts to your organization's policy before deployment.
