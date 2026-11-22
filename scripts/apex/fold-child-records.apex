// Moves the old child records (bill lines, payments, estimate lines, job slip
// lines, Service Book entries) into their parent records and deletes them; see
// ChildRecordFold and architecture.md, Forty-second. Safe to run any number of
// times, on any org. Each run handles a share and prints FOLD-REMAINING: <n>;
// Deploy-ToClientOrg.ps1 runs it until that is 0.
//
// Set dryRun to true to see what it would do and change nothing.
Boolean dryRun = false;

for (String line : ChildRecordFold.run(dryRun)) {
    System.debug(LoggingLevel.ERROR, line);
}
