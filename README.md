# WindowsAdminManagement

PowerShell scripts for creating and detecting a dedicated local administrator account on Windows endpoints.

## Scripts

- `scripts/New-ManagedLocalAdmin.ps1` — creates or updates `LocalAdmin`, enables it, adds it to the local `Administrators` group, verifies the configuration, and writes a completion marker.
- `scripts/Detect-ManagedLocalAdmin.ps1` — returns exit code `0` when `LocalAdmin` exists, is enabled, and is a member of the local `Administrators` group.
- `scripts/Invoke-LocalAdminCleanup.ps1` — audits local `Administrators` membership, retains approved admins (e.g. `LocalAdmin`, `LAPSAdmin`), safely preserves the built-in `-500` administrator and optional Entra ID role SIDs, and purges unauthorized accounts and orphaned SIDs.
- `scripts/Detect-LocalAdminCleanup.ps1` — detection script for Intune Endpoint Analytics Remediations; exits `0` if compliant, or `1` if unauthorized accounts are detected.

## Intune example

Install command:

```text
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\New-ManagedLocalAdmin.ps1
```

Use the detection script as the custom detection rule where supported.

## Security warning

This repository is public. The password in the example script is a placeholder only:

```text
ChangeMe!2026
```

Do not replace it with a production credential and commit that credential to Git. For enterprise environments, prefer Windows LAPS or another per-device credential management solution.
