#requires -Version 5.1
<#
.SYNOPSIS
Detects directly listed Microsoft Entra users in local Administrators.
.DESCRIPTION
Win32 (default): exit 0 plus stdout when detected; exit 1 for targets or errors.
Remediation mode: exit 1 for targets; exit 2 for errors (no remediation triggered).
No files or accounts are changed. Match exclusions in the cleanup script.
#>
[CmdletBinding()]
param(
    [string[]]$ExcludedMemberSids = @(),
    [ValidateSet('Win32', 'Remediation')]
    [string]$DeploymentType = 'Win32'
)

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
    if ($DeploymentType -eq 'Remediation') { exit 2 }
    exit 1
}
