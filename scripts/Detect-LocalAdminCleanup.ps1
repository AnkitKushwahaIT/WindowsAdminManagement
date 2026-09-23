# ============================================================
# WindowsAdminManagement - Detect Unauthorized Local Admins
# Exit 0 = Compliant (No unauthorized admins found)
# Exit 1 = Non-Compliant (Unauthorized admins detected)
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$ApprovedAdmins = @("LocalAdmin", "LAPSAdmin")
$PreserveEntraAdmins = $true
$AdministratorsGroup = "Administrators"

$AdminGroupADSI = [ADSI]"WinNT://./$AdministratorsGroup,group"
$Members = @($AdminGroupADSI.Invoke("Members"))
$BuiltInAdminSid = (Get-LocalUser | Where-Object { $_.SID.Value -like "S-1-5-21-*-500" }).SID.Value

$UnauthorizedFound = @()

foreach ($Member in $Members) {
    $MemberName = $Member.GetType().InvokeMember("Name", "GetProperty", $null, $Member, $null)
    $MemberSID  = $null
    try {
        $ObjectBytes = $Member.GetType().InvokeMember("objectSid", "GetProperty", $null, $Member, $null)
        if ($ObjectBytes) {
            $MemberSID = (New-Object System.Security.Principal.SecurityIdentifier($ObjectBytes, 0)).Value
        }
    } catch {}

    # Protect built-in -500 admin
    if ($MemberSID -and $MemberSID -eq $BuiltInAdminSid) { continue }

    # Protect Entra ID role SIDs
    if ($PreserveEntraAdmins -and $MemberSID -and $MemberSID -like "S-1-12-1-*") { continue }

    # Check approved list
    if ($ApprovedAdmins -contains $MemberName) { continue }

    $UnauthorizedFound += $MemberName
}

if ($UnauthorizedFound.Count -gt 0) {
    Write-Output "Unauthorized administrators detected: $($UnauthorizedFound -join ', ')"
    exit 1
}

Write-Output "Compliant: No unauthorized administrators found."
exit 0
