/**
 * Backs the GST Returns screen (architecture.md §D.1, G3): a company's return
 * for one month or quarter, and the same as files for the CA. Marking a
 * period filed is WorkshopProfileController.setGstFiledUpTo, as on the
 * Workshop Profile.
 */
public with sharing class GstReturnController {

    public class GstReturnControllerException extends Exception {}

    public class Download {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    @AuraEnabled
    public static GstReturnService.GstReturn getReturn(Id companyId, Date startDate, Date endDate) {
        requirePeriod(startDate, endDate);
        return GstReturnService.build(companyId, startDate, endDate);
    }

    @AuraEnabled
    public static Download downloadReturn(Id companyId, Date startDate, Date endDate) {
        requirePeriod(startDate, endDate);
        GstReturnService.GstReturn ret = GstReturnService.build(companyId, startDate, endDate);
        Download download = new Download();
        download.fileName = GstReturnFiles.fileName(ret);
        download.base64Data = EncodingUtil.base64Encode(GstReturnFiles.zip(ret));
        return download;
    }

    // Returns are filed for whole months: a month, or the three of a quarter.
    private static void requirePeriod(Date startDate, Date endDate) {
        Boolean wholeMonths = startDate != null && endDate != null && startDate.day() == 1
            && endDate == GstFilingLock.monthEnd(endDate) && endDate > startDate
            && startDate.monthsBetween(endDate) <= 2;
        if (!wholeMonths) {
            throw new GstReturnControllerException('Pick a month or quarter.');
        }
    }
}
