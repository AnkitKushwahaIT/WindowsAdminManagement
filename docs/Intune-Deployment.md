# Intune Win32 deployment

Deploy cleanup as a **Windows app (Win32)** running as **System**, with a custom detection script that evaluates current Administrators membership. Use the same SID exclusions in the installer and detection copies.

## Detection design

Both scripts target names beginning with `AzureAD\` and `ObjectClass = User`. Do not match an email domain: Windows can list `AzureAD\LocalName` without a UPN or email address. An email-domain filter can incorrectly report detection success and cause Intune to skip cleanup.

| Detection result | Exit and stdout | Win32 outcome |
| --- | --- | --- |
| No targeted members | 0 with nonempty status text | Desired state detected; skip install |
| Targeted members exist | 1 with count | Not detected; required app can run cleanup |
| Membership/configuration error | 1 with error text | Not detected; investigate; installer independently checks membership |

Intune checks again after installation. Cleanup exits 0 only after successful removal and verification, and exits 1 for failures. A nonzero detection exit cannot be treated as successful installation. The state may already be satisfied before the installer has ever run.

Local users, LAPS accounts, domain/service entries, Entra groups and unresolved SID entries are retained. This is not an audit of effective administrator privileges through roles or groups.

## Prepare the package

1. Download the repository and make private deployment copies of the scripts.
2. If needed, edit `ExcludedMemberSids` defaults identically in both copies. Leave detection's `DeploymentType` default as `Win32`.
3. Put only `Invoke-LocalAdminCleanup.ps1` in a package source folder. Keep the detection file outside that folder for upload as a detection rule. Both scripts are standalone.
4. Use the [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool). For example, with source `C:\Packages\AdminCleanup\Source` and a separate output folder:

```powershell
.\IntuneWinAppUtil.exe -c C:\Packages\AdminCleanup\Source -s Invoke-LocalAdminCleanup.ps1 -o C:\Packages\AdminCleanup\Output -q
```

5. Upload the resulting `.intunewin` as a Windows app (Win32). Do not commit deployment packages or organization-specific settings to this public repository.

## App settings

| Setting | Value |
| --- | --- |
| Install behavior | System |
| Requirements | Your supported and piloted Windows versions and 64-bit architecture |
| Device restart behavior | No specific action; the script does not request restart |
| Return codes | 0 = Success; 1 = Failed |
| Detection rules | Use a custom detection script |
| Detection file | `Detect-LocalAdminCleanup.ps1` |
| Run detection as 32-bit on 64-bit clients | No |
| Enforce detection signature check | No for these unsigned files; enable after organizational signing and certificate trust deployment |
| Assignment | Required, initially a pilot device group |
| Allow available uninstall | No |

Use this install command to invoke 64-bit Windows PowerShell from Intune's 32-bit process:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Invoke-LocalAdminCleanup.ps1
```

To select an organization-specific log directory, append `-LogFolder "C:\CompanyIT\Logs"`. Use an administrator-controlled local directory. Do not add `-WhatIf` to the actual install command.

There is no automatic uninstall or rollback: restoring administrator access requires an approved account list. If the command-line form requires an uninstall command, use `cmd.exe /c exit 1` as an explicit unsupported-operation result, keep available uninstall disabled, and do not create an Uninstall assignment. It deliberately fails rather than claiming that account changes were undone. Recovery is described below.

Custom Win32 detection runs in the app's context; use System install behavior. The separate "Run using logged-on credentials" option belongs to Remediations, not this Win32 detection configuration.

## Pilot and acceptance

1. Verify a separate emergency administrator and, if applicable, LAPS password retrieval.
2. Inventory membership with `Get-LocalGroupMember -SID 'S-1-5-32-544' | Select-Object Name, ObjectClass, PrincipalSource, SID`.
3. On a disposable managed pilot device, preview cleanup with `-WhatIf`. Confirm only intended direct Entra users are targeted.
4. With a test user present, run detection in a separate PowerShell process and confirm exit 1. Apply cleanup; confirm exit 0, the removal log, and preservation of every non-target member.
5. Run detection again; confirm exit 0 with nonempty stdout. Confirm affected users can sign in after sign-out/sign-in and required support access remains available.
6. Test the Required Win32 assignment with a target present. Confirm installation and post-install detection succeed. Also test a device with no targets: installation should be skipped.
7. Reintroduce an authorized test entry on the pilot and confirm detection returns 1 again. Review subsequent Intune reevaluation before expanding to a limited group and then production.

Example manual detection check from an elevated 64-bit Windows PowerShell console:

```powershell
powershell.exe -NoProfile -File .\Detect-LocalAdminCleanup.ps1
$LASTEXITCODE
```

Required Win32 assignments can reoffer installation when later detection finds the state missing. This follows Intune reevaluation and retry behavior; it is not immediate prevention and is not a fixed cleanup schedule. An Available-only assignment does not provide the same required deployment behavior.

## Logs and troubleshooting

- Cleanup: `%ProgramData%\WindowsAdminManagement\LocalAdminCleanup.log`, unless overridden.
- Intune logs: `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\`.
- Check `AppWorkload.log`, `IntuneManagementExtension.log`, and relevant script-execution details such as `AgentExecutor.log` when present.
- App detected but installer skipped: inspect the actual local names, exclusions and detection output. Zero targets legitimately means the desired state is already present.
- Membership/module errors: verify 64-bit execution and investigate unresolvable members. Neither script silently treats an enumeration error as compliance.
- User still has admin access: inspect retained groups/Entra roles and existing logon sessions; direct-user cleanup does not remove every source of privileges.

No completion marker is created or consumed by this public version. Older internal installers may create one as an audit artifact; it must not replace live membership detection. Existing marker files do not affect these scripts.

For recovery, stop or exclude the affected device from Required assignment first. Use an approved administrator to restore only approved memberships from the local removal log. Unassignment does not undo previous changes; no automatic rollback occurs after partial failure.

## Optional recurring Remediations

Use the same cleanup script and detection script if you prefer scheduled Remediations. In the uploaded detection copy, change the `DeploymentType` default to `Remediation`; do not leave it as Win32. Configure matching exclusions in both uploaded copies, run using logged-on credentials **No**, and run in 64-bit PowerShell **Yes**. Use UTF-8 files and your chosen schedule.

In this mode, detection exit 1 means targets exist and triggers cleanup. Exit 2 indicates an evaluation error and does not request remediation. This separates errors from remediable drift. Signature trust and licensing prerequisites are documented by Microsoft.

## References

- [Win32 settings, detection and 64-bit install commands](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Remediations prerequisites and execution contract](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations)
- [LocalAccounts module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember?view=powershell-5.1)
