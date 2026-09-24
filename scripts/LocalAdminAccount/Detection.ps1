#requires -Version 5.1
<#
.SYNOPSIS
Win32 detection for a package-owned local administrator.
.DESCRIPTION
Exit 0 with stdout only if version, SID ownership, enabled state and direct
Administrators membership match. Exit 1 for drift or any evaluation error.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,19}$')]
    [string]$UserName = 'ManagedLocalAdmin'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$registryPath = "HKLM:\SOFTWARE\WindowsAdminManagement\LocalAdminAccounts\$UserName"
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $record = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
    $user = Get-LocalUser -Name $UserName -ErrorAction Stop
    if ($record.Version -ne '1.0.0' -or $record.AccountSid -ne $user.SID.Value -or -not $user.Enabled -or $user.SID.Value -match '-500$') {
        throw 'Version, ownership or enabled state does not match.'
    }
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    if (-not ($members | Where-Object { $_.SID.Value -eq $user.SID.Value })) { throw 'Account is not a direct local administrator.' }
    Write-Output "Detected: $UserName is enabled, package-owned and a direct local administrator."
    exit 0
}
catch {
    Write-Output "Not detected: $($_.Exception.Message)"
    exit 1
}
