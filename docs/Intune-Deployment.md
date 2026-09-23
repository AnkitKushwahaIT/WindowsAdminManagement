# Intune Deployment

## Win32 application

Package:

```text
New-ManagedLocalAdmin.ps1
Detect-ManagedLocalAdmin.ps1
```

Install command:

```text
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\New-ManagedLocalAdmin.ps1
```

Run in **System** context for device-level deployment.

Use `Detect-ManagedLocalAdmin.ps1` as the detection script.

> For production, do not deploy a single shared static local administrator password across all devices. Prefer Windows LAPS where supported.

## Intune Remediations (Endpoint Analytics)

For recurring enforcement and cleanup of unauthorized local administrators:

- **Detection Script**: `scripts/Detect-LocalAdminCleanup.ps1`
- **Remediation Script**: `scripts/Invoke-LocalAdminCleanup.ps1`
- **Run script in 64-bit PowerShell**: Yes
- **Run this script using the logged-on credentials**: No (Run as System)
