<#
.SYNOPSIS
    Deploys WS Biller to a new (or existing) client org and runs every
    post-deploy step a plain metadata deploy does not cover.

.DESCRIPTION
    Three real, confirmed problems make a naive deploy fail or get
    blocked, and this script exists specifically to avoid all three,
    every time:

    (A) On a brand-new org, the user driving the deploy has no
        Field-Level Security on this app's custom fields yet. FLS is
        never granted automatically to Metadata-API-created fields, not
        even to a System Administrator. Since this app's own permission
        set is the only thing that grants it, and a deploy's Apex test
        run executes as that same user, including Apex tests in the very
        first deploy to any new org means those tests fail en masse
        ("fields being inaccessible" / "No such column").

    (B) Splitting Apex out of that first deploy to work around (A) is
        NOT safe on every org: at least one real org has been observed
        validating, at deploy time, that every "@salesforce/apex/Class.
        method" import inside an LWC bundle resolves to an Apex class
        that already exists in the org - and that the permission set's
        classAccesses entries point at classes that already exist too.
        Since every single LWC in this project imports an Apex
        controller this way, a deploy that includes the LWCs and the
        permission set but excludes the Apex classes can fail on some
        orgs ("Unable to find Apex action class...", "no ApexClass
        named ... found") even though the identical split succeeded on
        a different org. This is inconsistent across orgs/releases, so
        the only reliable fix is to never split Apex out of the deploy
        at all - everything that can reference anything else deploys
        together, in one transaction, so every cross-reference resolves
        within that same payload regardless of which org is enforcing
        which checks.

    (C) On any org that has already seen this app's nightly scheduled
        job registered (every deploy after the first one), any Apex
        deploy is flatly rejected with "This schedulable class has jobs
        pending or in progress." Fix: abort it by name immediately
        before deploying, re-register it immediately after
        (post-install.apex already does this idempotently).

    Putting (A) and (B) together: the whole force-app tree deploys as
    ONE payload, with --test-level NoTestRun (sidesteps (A) - no Apex
    tests run during this deploy at all - and (B) is a non-issue once
    everything is in the same payload). The permission set is then
    assigned for real. Only THEN is a standalone Apex test run executed
    (sf apex run test, not a deploy) to prove the deployed code actually
    works correctly now that FLS exists - if that fails, it is a real
    problem, not a chicken-and-egg one.

    IMPORTANT PRODUCTION CAVEAT: Salesforce does not allow
    --test-level NoTestRun for deploys to a Production org that contain
    Apex. This script's approach is confirmed safe for Developer Edition
    and Sandbox orgs. For a real Production client org, NoTestRun will be
    rejected, and the standard fix for that specific case - bundling FLS
    grants onto the admin's own Profile metadata, deployed in the same
    transaction as everything else, so the running user already has FLS
    without a separate assignment step - has not been built or tested
    here yet. Do not assume this script works unmodified against a
    Production org until that is addressed.

    Full sequence, every time:

      1. Unschedule this app's own job, if present (no-op on a new org).
      2. Validate, then deploy for real, the entire force-app tree with
         --test-level NoTestRun, deleting what manifest/destructiveChangesPre.xml
         lists first (the retired child-record triggers and classes;
         --ignore-warnings, so an org without them is fine). The CLI only
         takes a delete list alongside a manifest, so a package.xml of the
         whole force-app tree is generated first; it's the same payload as
         --source-dir force-app, deployed in one transaction.
         2c. fold-child-records.apex, repeated until nothing is left: moves
         old bill lines, payments, estimate lines, job slip lines and Service
         Book entries into their parent records (a no-op once done, and on a
         new org). Run Retire-OldChildObjects.ps1 afterwards, once, to delete
         the empty objects.
      3. Assign WS_Biller_Full_Access to the target admin user.
      4. Run a standalone Apex test verification (not a deploy) to prove
         the deployed code actually passes now that FLS exists.
      5. post-install.apex - re-registers the nightly job (idempotent).
      6. smoke-test.apex - exercises the real create-a-bill flow end to
         end and rolls back.
      7. Prints the manual checklist for what genuinely can't be automated.

.PARAMETER TargetOrg
    Alias or username of the client org, already authenticated.

.PARAMETER AdminUsername
    Username of the client org's admin user to assign the permission set
    to. Required - step 4's own test run depends on this assignment
    having already happened.

.PARAMETER SkipSmokeTest
    Skip step 6. Use this only if Workshop_Profile__c and
    Job_Status_Stage__c have not been seeded yet for this client.

.EXAMPLE
    .\Deploy-ToClientOrg.ps1 -TargetOrg acmeMotors -AdminUsername admin@acmemotors.com
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetOrg,

    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,

    [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $repoRoot

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

Write-Step "1/7 Unscheduling this app's own jobs (no-op on a brand-new org)"
sf apex run --file scripts/apex/unschedule-jobs.apex --target-org $TargetOrg

Write-Step "2a/7 Validating the full deploy (NoTestRun - see script header for why)"
$manifestDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wsbiller-deploy-" + [guid]::NewGuid())
sf project generate manifest --source-dir force-app --output-dir $manifestDir --name package.xml
if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not build the deploy manifest from force-app. Nothing was deployed." -ForegroundColor Red
    exit 1
}
$manifest = Join-Path $manifestDir "package.xml"
sf project deploy start --manifest $manifest --target-org $TargetOrg --test-level NoTestRun --dry-run --wait 30 --pre-destructive-changes manifest/destructiveChangesPre.xml --ignore-warnings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Validation failed. Nothing was deployed. Fix the errors above before re-running." -ForegroundColor Red
    exit 1
}

Write-Step "2b/7 Deploying for real"
sf project deploy start --manifest $manifest --target-org $TargetOrg --test-level NoTestRun --wait 30 --pre-destructive-changes manifest/destructiveChangesPre.xml --ignore-warnings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Deploy failed. Nothing further will run." -ForegroundColor Red
    exit 1
}

Write-Step "2c/7 Moving old child records into their bills, estimates, job slips and cars (no-op once done)"
# Each run is one all-or-nothing transaction handling a share of the records.
$remaining = -1
for ($run = 1; $run -le 40 -and $remaining -ne 0; $run++) {
    $previousEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $foldOutput = sf apex run --file scripts/apex/fold-child-records.apex --target-org $TargetOrg 2>&1
    $foldExit = $LASTEXITCODE
    $ErrorActionPreference = $previousEAP
    $foldLines = $foldOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'USER_DEBUG' } | ForEach-Object { ($_ -split '\|')[-1] }
    $foldLines | ForEach-Object { Write-Host "  $_" }
    # -1 means "run again" (it has just given itself access, or has one more tidy-up to do).
    $match = $foldLines | Select-String -Pattern 'FOLD-REMAINING: (-?\d+)' | Select-Object -Last 1
    if ($foldExit -ne 0 -or -not $match) {
        $foldOutput | ForEach-Object { Write-Host $_ }
        Write-Host "Moving the old records failed (nothing from that run was changed). Fix the error above and re-run this script." -ForegroundColor Red
        exit 1
    }
    $remaining = [int]$match.Matches[0].Groups[1].Value
}
if ($remaining -ne 0) {
    Write-Host "The old records are not all moved after 40 runs (last count: $remaining). Re-run this script to continue." -ForegroundColor Red
    exit 1
}

Write-Step "2d/7 Keeping the end-user profile logged in for 24 hours"
# A profile has at most one session setting, and each org names it differently
# (e.g. Ws_biller_enduser_profile_profileSessionSetting1791699339703), so it
# can't be a fixed file in force-app: deploying one under another name fails with
# "A session setting with this profile already exists". This finds the org's
# own one (or makes it, if there's none) and sets 24 hours with no forced logout.
# Not fatal: the org-wide 24 hours from Security.settings already applies.
$endUserProfile = 'Ws biller enduser profile'
$sessionDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wsbiller-session-" + [guid]::NewGuid())
$previousEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    sf project retrieve start --metadata ProfileSessionSetting --target-org $TargetOrg --target-metadata-dir (Join-Path $sessionDir "retrieved") --unzip --wait 10 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not read the org's profile session settings" }
    $existing = Get-ChildItem -Path (Join-Path $sessionDir "retrieved") -Recurse -Filter "*.profileSessionSetting" |
        Where-Object { ([xml](Get-Content $_.FullName -Raw)).ProfileSessionSetting.profile -eq $endUserProfile } |
        Select-Object -First 1
    if ($existing) {
        $settingName = $existing.BaseName
        [xml]$setting = Get-Content $existing.FullName -Raw
    } else {
        $settingName = "Ws_Biller_End_User"
        [xml]$setting = Get-Content (Join-Path $repoRoot "scripts\deploy\templates\EndUserProfileSessionSetting.xml") -Raw
        $setting.ProfileSessionSetting.profile = $endUserProfile
    }
    $setting.ProfileSessionSetting.sessionTimeout = "1440"
    $setting.ProfileSessionSetting.forceLogout = "false"
    $deployDir = Join-Path $sessionDir "deploy"
    New-Item -ItemType Directory -Force (Join-Path $deployDir "profileSessionSettings") | Out-Null
    $setting.Save((Join-Path $deployDir "profileSessionSettings\$settingName.profileSessionSetting"))
    @"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types><members>$settingName</members><name>ProfileSessionSetting</name></types>
  <version>67.0</version>
</Package>
"@ | Set-Content -Path (Join-Path $deployDir "package.xml") -Encoding utf8
    sf project deploy start --metadata-dir $deployDir --target-org $TargetOrg --wait 10 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "deploying $settingName failed" }
    Write-Host "  $endUserProfile -> 24 hours, no forced logout ($settingName)."
} catch {
    Write-Host "  Couldn't set the end-user profile's session timeout ($_). The org-wide 24 hours still applies; set it by hand in Setup > Profiles > $endUserProfile > Session Settings if needed." -ForegroundColor Yellow
}
$ErrorActionPreference = $previousEAP

Write-Step "3/7 Assigning WS_Biller_Full_Access to $AdminUsername"
$previousEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$assignOutput = sf org assign permset --name WS_Biller_Full_Access --target-org $TargetOrg --on-behalf-of $AdminUsername 2>&1
$ErrorActionPreference = $previousEAP
$assignOutput | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    if (($assignOutput -join "`n") -match "Duplicate PermissionSetAssignment") {
        Write-Host "Already assigned to $AdminUsername from an earlier run - continuing." -ForegroundColor Yellow
    } else {
        Write-Host "Permission set assignment failed. Step 4 will fail without this. Fix and re-run before continuing." -ForegroundColor Red
        exit 1
    }
}

Write-Step "4/7 Verifying the deployed code actually passes its tests now that FLS exists"
sf apex run test --target-org $TargetOrg --test-level RunLocalTests --synchronous --wait 30
if ($LASTEXITCODE -ne 0) {
    Write-Host "Test run failed. Unlike the deploy itself, this is NOT expected to fail -" -ForegroundColor Red
    Write-Host "the permission set is already assigned at this point, so a real failure here" -ForegroundColor Red
    Write-Host "means an actual bug, not the FLS chicken-and-egg problem. Investigate before continuing." -ForegroundColor Red
    exit 1
}

Write-Step "5/7 Re-registering the nightly cleanup job (idempotent)"
sf apex run --file scripts/apex/post-install.apex --target-org $TargetOrg
if ($LASTEXITCODE -ne 0) {
    Write-Host "post-install.apex failed. Check the output above." -ForegroundColor Yellow
}

if (-not $SkipSmokeTest) {
    Write-Step "6/7 Running the end-to-end smoke test (rolls itself back, leaves no data)"
    sf apex run --file scripts/apex/smoke-test.apex --target-org $TargetOrg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Smoke test failed. The most likely cause on a brand-new org is that" -ForegroundColor Red
        Write-Host "Workshop_Profile__c and Job_Status_Stage__c have not been seeded yet. Run" -ForegroundColor Red
        Write-Host "scripts/apex/seed-required-data-template.apex (edited for this client) first." -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "6/7 Skipped smoke test (-SkipSmokeTest set)." -ForegroundColor Yellow
}

Write-Step "7/7 Manual checklist - these cannot be scripted"
Write-Host "  1. Seed client-specific data (one-time, per client):"
Write-Host "     Copy scripts/apex/seed-required-data-template.apex, fill in the REPLACE_ME"
Write-Host "     values with this client's real business details, then run it once against"
Write-Host "     $TargetOrg. Without this, every bill creation throws immediately, and the"
Write-Host "     Jobs board has no columns."
Write-Host "  2. Assign the permission set to every other staff user, not just the admin."
Write-Host "     Command: sf org assign permset --name WS_Biller_Full_Access --target-org $TargetOrg --on-behalf-of USERNAME"
Write-Host "  3. Confirm the client's Salesforce edition supports everything this app uses"
Write-Host "     (Lightning Apps, custom Report Types, Scheduled Apex)."
Write-Host "  4. If this is a PRODUCTION org: NoTestRun above would have been rejected by"
Write-Host "     Salesforce. This script has not yet been adapted for that case - stop and"
Write-Host "     address it before using this script against a live Production org."
Write-Host "  5. Do the on-device walkthrough in the Salesforce Mobile App."
Write-Host "  6. (Optional) Seed Vehicle_Make_Model__c with common makes and models via"
Write-Host "     Data Loader. The app works correctly with it empty, just with no"
Write-Host "     autocomplete suggestions yet."
Write-Host "  7. On each shop PC (slow PCs especially; architecture.md, Forty-third), in Chrome:"
Write-Host "     - Settings > On startup > 'Continue where you left off' (keeps the login when Chrome is closed)."
Write-Host "     - Settings > Performance > Memory Saver > 'Always keep these sites active' > add"
Write-Host "       force.com (otherwise Chrome unloads the tab and the next click reloads everything)."
Write-Host "     - Keep one WS Biller tab open all day and move between screens inside it;"
Write-Host "       don't open screens in new tabs. Close other tabs and programs on a 2 GB PC."
Write-Host "  8. For quick Service Book entries, staff can use the Salesforce mobile app on"
Write-Host "     their phone: it stays logged in and opens on Service Book."
