#requires -Version 5.1
<#
.SYNOPSIS
Detects directly listed Microsoft Entra users in local Administrators.
.DESCRIPTION
Exit 0: no targeted users. Exit 1: targeted users found. Exit 2: detection error.
For Intune Remediations, exit 1 triggers remediation; errors do not trigger it.
No files or accounts are changed. Match exclusions in the cleanup script.
#>
[CmdletBinding()]
param([string[]]$ExcludedMemberSids = @())

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell.'
    }
    foreach ($sid in $ExcludedMemberSids) {
        $null = [Security.Principal.SecurityIdentifier]::new($sid)
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    $targets = @(
        foreach ($member in $members) {
            # Keep this predicate identical in the standalone cleanup script.
            if ($member.Name -match '^AzureAD\\' -and $member.ObjectClass -eq 'User') {
                if (-not $member.SID) { throw 'A targeted member has no SID; cannot safely identify it.' }
                if ($ExcludedMemberSids -notcontains $member.SID.Value) { $member }
            }
        }
    )
    if ($targets.Count -gt 0) {
        Write-Output "Noncompliant: $($targets.Count) targeted direct Entra user member(s)."
        exit 1
    }
    Write-Output 'Compliant: no targeted direct Entra user members. Other administrator memberships are outside this policy.'
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-Output ('Detection error: ' + $message.Substring(0, [Math]::Min(1200, $message.Length)))
    exit 2
}
