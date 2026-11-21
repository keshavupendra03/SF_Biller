// One-time: puts vehicle numbers (registration, chassis, engine), job slip
// battery numbers and the company IFSC already saved in small letters into
// capitals. Saving a record runs UpperCaseText through its trigger, so this
// just re-saves the ones that need it. Safe to run again: it only touches
// values that aren't in capitals yet. GSTINs were done by GstBackfillBatch.

List<Vehicle__c> vehicles = new List<Vehicle__c>();
for (Vehicle__c v : [SELECT Id, Name, Chassis_Number__c, Engine_Number__c FROM Vehicle__c LIMIT 9000]) {
    for (String s : new List<String>{ v.Name, v.Chassis_Number__c, v.Engine_Number__c }) {
        if (s != null && !s.trim().toUpperCase().equals(s)) {
            vehicles.add(v);
            break;
        }
    }
}
update vehicles;

List<Job_Slip__c> slips = new List<Job_Slip__c>();
for (Job_Slip__c j : [SELECT Id, Battery_Number__c FROM Job_Slip__c WHERE Battery_Number__c != null LIMIT 9000]) {
    if (!j.Battery_Number__c.trim().toUpperCase().equals(j.Battery_Number__c)) {
        slips.add(j);
    }
}
update slips;

List<Workshop_Profile__c> companies = new List<Workshop_Profile__c>();
for (Workshop_Profile__c w : [SELECT Id, Bank_IFSC__c FROM Workshop_Profile__c WHERE Bank_IFSC__c != null]) {
    if (!w.Bank_IFSC__c.trim().toUpperCase().equals(w.Bank_IFSC__c)) {
        companies.add(w);
    }
}
update companies;

System.debug('Put in capitals: ' + vehicles.size() + ' vehicles, ' + slips.size() + ' job slips, ' + companies.size() + ' companies.');
