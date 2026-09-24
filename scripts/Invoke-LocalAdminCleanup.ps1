#requires -Version 5.1
<#
.SYNOPSIS
Removes directly listed Microsoft Entra users from local Administrators.
.DESCRIPTION
Preserves local/domain accounts, groups, unresolved entries and excluded SIDs.
Does not assess effective role-based privileges or configure Windows LAPS.
Run elevated in 64-bit Windows PowerShell 5.1. Preview with -WhatIf.
.PARAMETER ExcludedMemberSids
Exact user SIDs to retain. Match this configuration in the detection script.
.PARAMETER LogFolder
Local log destination. Defaults to ProgramData\WindowsAdminManagement.
.EXAMPLE
.\Invoke-LocalAdminCleanup.ps1 -WhatIf
.EXAMPLE
.\Invoke-LocalAdminCleanup.ps1 -ExcludedMemberSids 'S-1-12-1-111-222-333-444'
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$ExcludedMemberSids = @(),
    [string]$LogFolder = (Join-Path $env:ProgramData 'WindowsAdminManagement')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$groupSid = 'S-1-5-32-544'
$logFile = Join-Path $LogFolder 'LocalAdminCleanup.log'

function Write-CleanupLog {
    param([string]$Message)
    if ($WhatIfPreference) { Write-Verbose $Message -Verbose; return }
    Add-Content -LiteralPath $logFile -Value ('{0:u} {1}' -f (Get-Date), $Message) -Encoding UTF8 -ErrorAction Stop
}

function Get-CleanupTargets {
    param([object[]]$Members)
    foreach ($member in $Members) {
        # Regex uses two backslashes to match one literal backslash.
        # Keep this predicate identical in the standalone detection script.
        if ($member.Name -match '^AzureAD\\' -and $member.ObjectClass -eq 'User') {
            if (-not $member.SID) { throw 'A targeted member has no SID; cannot safely identify it.' }
            if ($ExcludedMemberSids -notcontains $member.SID.Value) { $member }
        }
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run elevated or as SYSTEM.'
    }
    foreach ($sid in $ExcludedMemberSids) {
        $null = [Security.Principal.SecurityIdentifier]::new($sid)
    }
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
    $members = @(Get-LocalGroupMember -SID $groupSid -ErrorAction Stop)
    $targets = @(Get-CleanupTargets -Members $members)
    if (-not $WhatIfPreference) {
        New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    Write-CleanupLog "START: members=$($members.Count); targets=$($targets.Count); excludedSids=$($ExcludedMemberSids.Count)"
    $removed = 0
    $failed = 0
    foreach ($member in $targets) {
        if ($PSCmdlet.ShouldProcess("$($member.Name) [$($member.SID.Value)]", 'Remove from local Administrators')) {
            Write-CleanupLog "TARGET: $($member.Name) [$($member.SID.Value)]"
            try {
                Remove-LocalGroupMember -SID $groupSid -Member $member.SID.Value -Confirm:$false -ErrorAction Stop
                $removed++
            }
            catch {
                $failed++
                Write-CleanupLog "FAILED: $($member.SID.Value); $($_.Exception.Message)"
                continue
            }
            Write-CleanupLog "REMOVED: $($member.SID.Value)"
        }
    }
    if ($WhatIfPreference) {
        Write-Output "Preview complete: $($targets.Count) targeted member(s); no changes made. This is not a compliance result."
        exit 0
    }
    $finalMembers = @(Get-LocalGroupMember -SID $groupSid -ErrorAction Stop)
    $remaining = @(Get-CleanupTargets -Members $finalMembers)
    $summary = "Removed=$removed; failed=$failed; remaining targets=$($remaining.Count); retained members=$($finalMembers.Count)."
    Write-CleanupLog $summary
    if ($failed -gt 0 -or $remaining.Count -gt 0) { throw "Cleanup incomplete. $summary" }
    Write-CleanupLog 'SUCCESS: no targeted direct Entra user members remain.'
    Write-Output "Compliant with direct Entra user cleanup policy. $summary"
    exit 0
}
catch {
    $message = $_.Exception.Message
    try { Write-CleanupLog "ERROR: $message" } catch { }
    Write-Output ('Cleanup failed: ' + $message.Substring(0, [Math]::Min(1200, $message.Length)))
    exit 1
}
