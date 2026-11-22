<#
.SYNOPSIS
    Deletes the five child objects that WS Biller no longer uses, once their
    records have been moved into their parents.

.DESCRIPTION
    Bill lines, payments, estimate lines, job slip lines and Service Book
    entries are now stored inside their bill, estimate, job slip or car, to
    save data storage (architecture.md, Forty-second).
    Deploy-ToClientOrg.ps1 moves the old records across
    (fold-child-records.apex) but leaves the empty objects in place. This
    script deletes them: Bill_Line_Item__c, Payment__c, Estimate_Line_Item__c,
    Job_Slip_Line__c and Service_Entry__c.

    Run it once per existing org, after Deploy-ToClientOrg.ps1 has finished
    and you've checked a few old bills, estimates, job slips and Service Book
    cards look right. It refuses to run if any of the objects still has a
    record. A new org never had these objects; running it there just reports
    that.

    Salesforce keeps a deleted object for 15 days (Setup > Object Manager >
    Deleted Objects), where it can be restored.

.PARAMETER TargetOrg
    Alias or username of the org, already authenticated.

.EXAMPLE
    .\Retire-OldChildObjects.ps1 -TargetOrg acmeMotors
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetOrg
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $repoRoot

$objects = @('Bill_Line_Item__c', 'Payment__c', 'Estimate_Line_Item__c', 'Job_Slip_Line__c', 'Service_Entry__c')
$present = @()
foreach ($object in $objects) {
    $previousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = sf data query --query "SELECT COUNT() FROM $object" --target-org $TargetOrg --json 2>$null
    $ErrorActionPreference = $previousEAP
    $result = ($raw -join "`n") | ConvertFrom-Json
    if ($result.status -ne 0) {
        Write-Host "$object - not in this org (already deleted, or never there)."
        continue
    }
    $count = [int]$result.result.totalSize
    Write-Host "$object - $count records."
    if ($count -gt 0) {
        Write-Host "It still has records. Run Deploy-ToClientOrg.ps1 first (step 2c moves them). Nothing was deleted." -ForegroundColor Red
        exit 1
    }
    $present += $object
}

if ($present.Count -eq 0) {
    Write-Host "Nothing to delete." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Deleting: $($present -join ', ')" -ForegroundColor Cyan
sf project deploy start --manifest manifest/emptyPackage.xml --post-destructive-changes manifest/retireChildObjects.xml --target-org $TargetOrg --ignore-warnings --wait 30
if ($LASTEXITCODE -ne 0) {
    Write-Host "Deleting the objects failed. Nothing was deleted; see the error above." -ForegroundColor Red
    exit 1
}
Write-Host "Done. The objects can be restored for 15 days from Setup > Object Manager > Deleted Objects." -ForegroundColor Green
