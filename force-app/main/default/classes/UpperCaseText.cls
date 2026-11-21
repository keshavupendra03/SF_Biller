/**
 * Stores codes people read off a car or a certificate in capitals, whichever
 * screen, import or script saved them: vehicle registration, chassis and engine
 * numbers (VehicleTrigger), the battery number on a job slip (JobSlipTrigger)
 * and the bank IFSC (WorkshopProfileTrigger). GSTINs are done by
 * GstPartyDetails. Leading and trailing spaces go too; spaces inside stay as
 * typed ("MP 09 AB 1234").
 */
public with sharing class UpperCaseText {

    public static final List<SObjectField> VEHICLE_FIELDS = new List<SObjectField>{
        Vehicle__c.Name, Vehicle__c.Chassis_Number__c, Vehicle__c.Engine_Number__c
    };
    public static final List<SObjectField> JOB_SLIP_FIELDS = new List<SObjectField>{ Job_Slip__c.Battery_Number__c };
    public static final List<SObjectField> COMPANY_FIELDS = new List<SObjectField>{ Workshop_Profile__c.Bank_IFSC__c };

    public static void apply(List<SObject> records, List<SObjectField> fields) {
        for (SObject record : records) {
            for (SObjectField field : fields) {
                String value = (String) record.get(field);
                if (value != null) {
                    String tidy = value.trim().toUpperCase();
                    // Apex's own == ignores case, so compare exactly.
                    if (!tidy.equals(value)) {
                        record.put(field, tidy);
                    }
                }
            }
        }
    }
}
