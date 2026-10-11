@isTest
private class AmountInWordsServiceTest {

    @isTest
    static void matchesARealInvoiceTotalExactly() {
        System.assertEquals(
            'Thirty Seven Thousand One Hundred and Seven Rupees only',
            AmountInWordsService.convert(37107.00)
        );
    }

    @isTest
    static void zero() {
        System.assertEquals('Zero Rupees only', AmountInWordsService.convert(0));
    }

    @isTest
    static void belowTwenty() {
        System.assertEquals('Seven Rupees only', AmountInWordsService.convert(7));
    }

    @isTest
    static void exactHundredNoAndNeeded() {
        System.assertEquals('One Hundred Rupees only', AmountInWordsService.convert(100));
    }

    @isTest
    static void hundredPlusRemainderUsesAnd() {
        System.assertEquals(
            'One Hundred and Five Rupees only',
            AmountInWordsService.convert(105)
        );
    }

    @isTest
    static void thousands() {
        System.assertEquals('One Thousand Rupees only', AmountInWordsService.convert(1000));
        System.assertEquals(
            'Ninety Nine Thousand Nine Hundred and Ninety Nine Rupees only',
            AmountInWordsService.convert(99999)
        );
    }

    @isTest
    static void lakhs() {
        System.assertEquals(
            'One Lakh Fifty Thousand Rupees only',
            AmountInWordsService.convert(150000)
        );
    }

    @isTest
    static void crores() {
        System.assertEquals(
            'One Crore Twenty Three Lakh Forty Five Thousand Six Hundred and Seventy Eight Rupees only',
            AmountInWordsService.convert(12345678)
        );
    }

    @isTest
    static void includesPaiseWhenPresent() {
        System.assertEquals(
            'One Thousand One Hundred and Eighty Rupees and Fifty Paise only',
            AmountInWordsService.convert(1180.50)
        );
    }

    @isTest
    static void roundsPaiseToTheNearestWholePaisa() {
        System.assertEquals('One Hundred Rupees only', AmountInWordsService.convert(99.999));
    }
}
