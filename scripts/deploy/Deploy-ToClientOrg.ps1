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
         --test-level NoTestRun.
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
sf project deploy start --source-dir force-app --target-org $TargetOrg --test-level NoTestRun --dry-run --wait 30
if ($LASTEXITCODE -ne 0) {
    Write-Host "Validation failed. Nothing was deployed. Fix the errors above before re-running." -ForegroundColor Red
    exit 1
}

Write-Step "2b/7 Deploying for real"
sf project deploy start --source-dir force-app --target-org $TargetOrg --test-level NoTestRun --wait 30
if ($LASTEXITCODE -ne 0) {
    Write-Host "Deploy failed. Nothing further will run." -ForegroundColor Red
    exit 1
}

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
