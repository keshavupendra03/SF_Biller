@isTest
private class GstRulesTest {

    // Real-format GSTINs whose last character is the correct check character.
    private static final String MP_GSTIN = '23AAACI7904G1ZV';
    private static final String MH_GSTIN = '27AAPFU0939F1ZV';

    @isTest
    static void stateCode_understandsTheWaysAStateGetsTyped() {
        for (String typed : new List<String>{
            'Madhya Pradesh', 'madhya pradesh', 'Madhyapradesh', 'MADHYA PRADESH ', 'MP', 'm.p.', 'Mp',
            '23', '23-Madhya Pradesh', '23 - MP', '23 Madhya Pradesh', '23. madhyapradesh'
        }) {
            System.assertEquals('23', GstRules.stateCode(typed), typed);
        }
        System.assertEquals('01', GstRules.stateCode('Jammu & Kashmir'));
        System.assertEquals('07', GstRules.stateCode('New Delhi'));
        System.assertEquals('21', GstRules.stateCode('Orissa'));
        System.assertEquals('36', GstRules.stateCode('TS'));
        System.assertEquals('34', GstRules.stateCode('Pondicherry'));
        System.assertEquals('97', GstRules.stateCode('Other Territory'));
    }

    @isTest
    static void stateCode_refusesWhatIsNotAState() {
        for (String typed : new List<String>{ 'Ujjain', 'Indore MP', '99', '00', '27-Madhya Pradesh', 'XYZ', '2 3' }) {
            System.assertEquals(null, GstRules.stateCode(typed), typed);
        }
        System.assertEquals(null, GstRules.stateCode(null));
        System.assertEquals(null, GstRules.stateCode('  '));
    }

    @isTest
    static void retiredCodes_onlyByNumber_namesMeanTheCurrentCode() {
        System.assertEquals('26', GstRules.stateCode('Daman and Diu'), 'Merged into 26 in 2020.');
        System.assertEquals('37', GstRules.stateCode('Andhra Pradesh'), '28 was Andhra Pradesh before 2014.');
        System.assertEquals('25', GstRules.stateCode('25'), 'An older GSTIN can still begin with 25.');
        System.assertEquals('Daman and Diu', GstRules.stateName('25'));
    }

    @isTest
    static void stateName_isTheStoredAndPrintedName() {
        System.assertEquals('Madhya Pradesh', GstRules.stateName('mp'));
        System.assertEquals('Dadra and Nagar Haveli and Daman and Diu', GstRules.stateName('DNH'));
        System.assertEquals(null, GstRules.stateName('Ujjain'));
        System.assertEquals('Maharashtra', GstRules.stateNameForCode('27'));
        System.assertEquals(null, GstRules.stateNameForCode(null));
    }

    @isTest
    static void isValidGstin_checksTheFormatStateAndCheckCharacter() {
        System.assert(GstRules.isValidGstin(MP_GSTIN));
        System.assert(GstRules.isValidGstin(MH_GSTIN));
        System.assert(GstRules.isValidGstin(' 27aapfu0939f1zv '), 'Case and spaces are tidied first.');

        System.assert(!GstRules.isValidGstin('27AAPFU0939F1ZW'), 'Wrong check character.');
        System.assert(!GstRules.isValidGstin('27AAPFU0938F1ZV'), 'One digit mistyped.');
        System.assert(!GstRules.isValidGstin('27AAPUF0939F1ZV'), 'Two letters swapped.');
        System.assert(!GstRules.isValidGstin('99AAPFU0939F1ZV'), 'No such state code.');
        System.assert(!GstRules.isValidGstin('27AAPFU0939F1Z'), 'Too short.');
        System.assert(!GstRules.isValidGstin('27AAPFU0939F1ZVX'), 'Too long.');
        System.assert(!GstRules.isValidGstin('27AAPFU0939F0ZV'), 'Entity number can\'t be 0.');
        System.assert(!GstRules.isValidGstin(null));
        System.assert(!GstRules.isValidGstin(''));
    }

    @isTest
    static void checkCharacter_matchesThePublishedExample() {
        System.assertEquals('V', GstRules.checkCharacter('27AAPFU0939F1Z'));
    }

    @isTest
    static void stateNameForGstin_onlyForAValidOne() {
        System.assertEquals('Madhya Pradesh', GstRules.stateNameForGstin(MP_GSTIN));
        System.assertEquals('Maharashtra', GstRules.stateNameForGstin(MH_GSTIN));
        System.assertEquals(null, GstRules.stateNameForGstin('23AAACI7904G1ZX'));
    }

    @isTest
    static void normalizeGstin_upperCaseNoSpaces_blankIsNull() {
        System.assertEquals('23AAACI7904G1ZV', GstRules.normalizeGstin(' 23aaa ci7904g1zv '));
        System.assertEquals(null, GstRules.normalizeGstin('   '));
    }

    @isTest
    static void isGstRate_onlyRatesThatExist() {
        for (Decimal rate : new List<Decimal>{ 0, 0.25, 3, 5, 5.00, 12, 18, 18.0, 28, 40 }) {
            System.assert(GstRules.isGstRate(rate), String.valueOf(rate));
        }
        for (Decimal rate : new List<Decimal>{ 81, 17, 2, 100, -18, 18.5 }) {
            System.assert(!GstRules.isGstRate(rate), String.valueOf(rate));
        }
        System.assert(!GstRules.isGstRate(null));
    }

    @isTest
    static void rateText_printsRatesPlainly() {
        System.assertEquals('40', GstRules.rateText(40));
        System.assertEquals('18', GstRules.rateText(18.00));
        System.assertEquals('0.1', GstRules.rateText(0.10));
        System.assertEquals('7.5', GstRules.rateText(7.50));
        System.assertEquals('0', GstRules.rateText(0.00));
        System.assert(GstRules.gstRatesText().endsWith('28 or 40'), GstRules.gstRatesText());
    }

    @isTest
    static void requireGstRates_namesTheLineWithAWrongRate() {
        BillController.LineItemInput good = new BillController.LineItemInput();
        good.description = 'Engine Oil';
        good.taxRatePercent = 18;
        BillController.LineItemInput bad = new BillController.LineItemInput();
        bad.description = 'Brake Pad';
        bad.taxRatePercent = 81;
        GstRules.requireGstRates(new List<BillController.LineItemInput>{ good });
        GstRules.requireGstRates(null);

        try {
            GstRules.requireGstRates(new List<BillController.LineItemInput>{ good, bad });
            System.assert(false, 'Expected 81% to be refused.');
        } catch (GstRules.GstRulesException e) {
            System.assert(e.getMessage().contains('81%'), e.getMessage());
            System.assert(e.getMessage().contains('Brake Pad'), e.getMessage());
        }
    }

    @isTest
    static void uqcFor_mapsCommonUnitWritings() {
        System.assertEquals('PCS', GstRules.uqcFor('pcs'));
        System.assertEquals('PCS', GstRules.uqcFor('Piece'));
        System.assertEquals('LTR', GstRules.uqcFor('Ltr.'));
        System.assertEquals('LTR', GstRules.uqcFor('litre'));
        System.assertEquals('SET', GstRules.uqcFor('Set'));
        System.assertEquals('NOS', GstRules.uqcFor('Nos'));
        System.assertEquals('PRS', GstRules.uqcFor('pair'));
        System.assertEquals(null, GstRules.uqcFor('bundle of joy'));
        System.assertEquals(null, GstRules.uqcFor(''));
    }
}
