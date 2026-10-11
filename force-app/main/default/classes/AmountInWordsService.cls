/**
 * Converts a rupee amount to Indian-English words for the invoice/estimate
 * PDF's "Amount in Words" line, e.g. 37107.00 -> "Thirty Seven Thousand One
 * Hundred and Seven Rupees only". Indian numbering (Lakh/Crore), not
 * Million/Billion.
 */
public with sharing class AmountInWordsService {

    private static final List<String> ONES = new List<String>{
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
        'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
        'Seventeen', 'Eighteen', 'Nineteen'
    };

    private static final List<String> TENS = new List<String>{
        '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    };

    public static String convert(Decimal amount) {
        Integer rupees = amount.intValue();
        Decimal paiseDecimal = (amount - rupees) * 100;
        Integer paise = paiseDecimal.setScale(0, System.RoundingMode.HALF_UP).intValue();
        if (paise >= 100) {
            // Floating-point-style rounding can push .995+ up to exactly
            // 100 paise — that's really the next rupee, not "100 Paise".
            rupees += 1;
            paise = 0;
        }

        String rupeeWords = rupees == 0 ? 'Zero' : convertInteger(rupees);
        String result = rupeeWords + ' Rupees';
        if (paise > 0) {
            result += ' and ' + convertInteger(paise) + ' Paise';
        }
        result += ' only';
        return result;
    }

    private static String convertInteger(Integer value) {
        if (value == 0) {
            return 'Zero';
        }

        Integer crore = value / 10000000;
        Integer lakh = Math.mod(value, 10000000) / 100000;
        Integer thousand = Math.mod(value, 100000) / 1000;
        Integer hundred = Math.mod(value, 1000);

        List<String> parts = new List<String>();
        if (crore > 0) parts.add(convertBelowThousand(crore) + ' Crore');
        if (lakh > 0) parts.add(convertBelowThousand(lakh) + ' Lakh');
        if (thousand > 0) parts.add(convertBelowThousand(thousand) + ' Thousand');
        if (hundred > 0) parts.add(convertBelowThousand(hundred));

        return String.join(parts, ' ');
    }

    private static String convertBelowThousand(Integer value) {
        Integer hundredsDigit = value / 100;
        Integer remainder = Math.mod(value, 100);

        List<String> parts = new List<String>();
        if (hundredsDigit > 0) {
            parts.add(ONES[hundredsDigit] + ' Hundred');
            if (remainder > 0) parts.add('and');
        }
        if (remainder > 0) {
            parts.add(convertBelowHundred(remainder));
        }
        return String.join(parts, ' ');
    }

    private static String convertBelowHundred(Integer value) {
        if (value < 20) {
            return ONES[value];
        }
        Integer tensDigit = value / 10;
        Integer onesDigit = Math.mod(value, 10);
        return onesDigit == 0 ? TENS[tensDigit] : TENS[tensDigit] + ' ' + ONES[onesDigit];
    }
}
