// Safe, non-destructive smoke test: exercises the core create-a-bill flow
// end-to-end through the real controllers (customer -> inline new vehicle
// -> line item with GST -> atomic invoice numbering), then rolls back
// every change so nothing is left behind in the org. Run this right after
// a deploy + post-install.apex + seed-required-data-template.apex, before
// handing a freshly-deployed client org over, to catch anything a
// metadata-only deploy can't — most importantly, this throws immediately
// and clearly if Workshop_Profile__c hasn't been seeded yet, instead of
// that surfacing later as a confusing failure the first time real staff
// try to create a bill.

Savepoint sp = Database.setSavepoint();
try {
    Customer__c customer = new Customer__c(Name = 'SMOKE TEST Customer', Phone__c = '9999999999');
    insert customer;

    BillController.CreateBillRequest request = new BillController.CreateBillRequest();
    request.customerId = customer.Id;

    CustomerController.NewVehicleInput vehicle = new CustomerController.NewVehicleInput();
    vehicle.registrationNumber = 'SMOKE-TEST-1234';
    vehicle.make = 'Smoke';
    vehicle.model = 'Test';
    request.newVehicle = vehicle;

    BillController.LineItemInput line = new BillController.LineItemInput();
    line.description = 'Smoke test line';
    line.quantity = 1;
    line.unitPrice = 1000;
    line.taxRatePercent = 18;
    request.lineItems = new List<BillController.LineItemInput>{ line };

    BillController.BillSummary summary = BillController.createBill(request);

    if (String.isBlank(summary.invoiceNumber)) {
        throw new System.AssertException('Invoice number was blank — numbering sequence did not run correctly.');
    }
    if (summary.totalAmount != 1180) {
        throw new System.AssertException(
            'Expected total 1180 (1000 + 18% GST) but got ' + summary.totalAmount + ' — GST calculation looks wrong.'
        );
    }

    System.debug('SMOKE TEST PASSED — invoice number: ' + summary.invoiceNumber
        + ', financial year: ' + summary.financialYear
        + ', total: ' + summary.totalAmount);
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'SMOKE TEST FAILED: ' + e.getMessage());
    throw e;
} finally {
    Database.rollback(sp);
    System.debug('Rolled back — no test data left behind in this org.');
}
