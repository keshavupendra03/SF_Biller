/**
 * GST reference data and checks in one place, so every screen, trigger and
 * report agrees: GST state codes, the GSTIN format and check digit, the GST
 * rates that exist, and GST units (UQC). lwc/gst holds the same lists for the
 * screens; GstRulesTest and gst.test.js check both against the same examples.
 */
public with sharing class GstRules {

    public class GstRulesException extends Exception {}

    // GST state codes. 25 (Daman and Diu) and 28 (Andhra Pradesh before 2014)
    // are no longer given out, but can still begin an older GSTIN.
    private static final Map<String, String> STATE_NAMES = new Map<String, String>{
        '01' => 'Jammu and Kashmir',
        '02' => 'Himachal Pradesh',
        '03' => 'Punjab',
        '04' => 'Chandigarh',
        '05' => 'Uttarakhand',
        '06' => 'Haryana',
        '07' => 'Delhi',
        '08' => 'Rajasthan',
        '09' => 'Uttar Pradesh',
        '10' => 'Bihar',
        '11' => 'Sikkim',
        '12' => 'Arunachal Pradesh',
        '13' => 'Nagaland',
        '14' => 'Manipur',
        '15' => 'Mizoram',
        '16' => 'Tripura',
        '17' => 'Meghalaya',
        '18' => 'Assam',
        '19' => 'West Bengal',
        '20' => 'Jharkhand',
        '21' => 'Odisha',
        '22' => 'Chhattisgarh',
        '23' => 'Madhya Pradesh',
        '24' => 'Gujarat',
        '25' => 'Daman and Diu',
        '26' => 'Dadra and Nagar Haveli and Daman and Diu',
        '27' => 'Maharashtra',
        '28' => 'Andhra Pradesh (Old)',
        '29' => 'Karnataka',
        '30' => 'Goa',
        '31' => 'Lakshadweep',
        '32' => 'Kerala',
        '33' => 'Tamil Nadu',
        '34' => 'Puducherry',
        '35' => 'Andaman and Nicobar Islands',
        '36' => 'Telangana',
        '37' => 'Andhra Pradesh',
        '38' => 'Ladakh',
        '97' => 'Other Territory'
    };

    // Ways a state gets typed (lower case, letters only), beyond its own name.
    // Two-letter forms are the vehicle registration codes staff know best.
    private static final Map<String, String> STATE_ALIASES = new Map<String, String>{
        'jk' => '01', 'hp' => '02', 'pb' => '03', 'ch' => '04', 'uk' => '05', 'ua' => '05',
        'uttaranchal' => '05', 'hr' => '06', 'dl' => '07', 'newdelhi' => '07', 'nctofdelhi' => '07',
        'delhinct' => '07', 'rj' => '08', 'up' => '09', 'br' => '10', 'sk' => '11', 'ar' => '12',
        'nl' => '13', 'mn' => '14', 'mz' => '15', 'tr' => '16', 'ml' => '17', 'as' => '18',
        'wb' => '19', 'jh' => '20', 'od' => '21', 'or' => '21', 'orissa' => '21', 'cg' => '22',
        'ct' => '22', 'chattisgarh' => '22', 'mp' => '23', 'gj' => '24', 'dd' => '26', 'dn' => '26',
        'dnh' => '26', 'damananddiu' => '26', 'dadraandnagarhaveli' => '26', 'mh' => '27',
        'ka' => '29', 'ga' => '30', 'ld' => '31', 'kl' => '32', 'tn' => '33', 'py' => '34',
        'pondicherry' => '34', 'an' => '35', 'andamanandnicobar' => '35', 'ts' => '36', 'tg' => '36',
        'ap' => '37', 'la' => '38'
    };

    // Codes no longer given to a typed state name: those names now mean 26 and 37.
    private static final Set<String> RETIRED_CODES = new Set<String>{ '25', '28' };

    private static final String GSTIN_CHARACTERS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    // Every rate in the GST schedules, including the September 2025 40% slab.
    private static final List<Decimal> GST_RATES = new List<Decimal>{ 0, 0.1, 0.25, 1, 1.5, 3, 5, 6, 7.5, 12, 18, 28, 40 };

    // GST units (UQC) by how they get written on parts and lines.
    private static final Map<String, String> UNIT_ALIASES = new Map<String, String>{
        'pc' => 'PCS', 'pcs' => 'PCS', 'piece' => 'PCS', 'pieces' => 'PCS',
        'no' => 'NOS', 'nos' => 'NOS', 'number' => 'NOS', 'numbers' => 'NOS',
        'l' => 'LTR', 'lt' => 'LTR', 'ltr' => 'LTR', 'ltrs' => 'LTR', 'litre' => 'LTR', 'liter' => 'LTR', 'litres' => 'LTR', 'liters' => 'LTR',
        'ml' => 'MLT', 'mlt' => 'MLT', 'kg' => 'KGS', 'kgs' => 'KGS', 'kilogram' => 'KGS', 'kilograms' => 'KGS',
        'g' => 'GMS', 'gm' => 'GMS', 'gms' => 'GMS', 'gram' => 'GMS', 'grams' => 'GMS',
        'm' => 'MTR', 'mtr' => 'MTR', 'mtrs' => 'MTR', 'meter' => 'MTR', 'metre' => 'MTR', 'meters' => 'MTR', 'metres' => 'MTR',
        'set' => 'SET', 'sets' => 'SET', 'pr' => 'PRS', 'prs' => 'PRS', 'pair' => 'PRS', 'pairs' => 'PRS',
        'box' => 'BOX', 'boxes' => 'BOX', 'btl' => 'BTL', 'bottle' => 'BTL', 'bottles' => 'BTL',
        'pac' => 'PAC', 'pack' => 'PAC', 'packs' => 'PAC', 'packet' => 'PAC', 'packets' => 'PAC', 'pkt' => 'PAC',
        'rol' => 'ROL', 'roll' => 'ROL', 'rolls' => 'ROL', 'can' => 'CAN', 'cans' => 'CAN',
        'doz' => 'DOZ', 'dozen' => 'DOZ', 'unt' => 'UNT', 'unit' => 'UNT', 'units' => 'UNT',
        'sqf' => 'SQF', 'sqft' => 'SQF', 'sqm' => 'SQM', 'bag' => 'BAG', 'bags' => 'BAG',
        'ctn' => 'CTN', 'carton' => 'CTN', 'drm' => 'DRM', 'drum' => 'DRM', 'ton' => 'TON', 'kme' => 'KME', 'oth' => 'OTH'
    };

    private static Map<String, String> stateKeys;

    // ---- states -------------------------------------------------------------

    /**
     * The GST state code for however a state was typed: "Madhya Pradesh",
     * "madhyapradesh", "MP", "M.P.", "23" or "23-Madhya Pradesh". Null when it
     * isn't a state, including a code and name that disagree ("27-MP").
     */
    public static String stateCode(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Matcher numbered = Pattern.compile('^(\\d{1,2})\\s*[-.:)]?\\s*(.*)$').matcher(text.trim());
        if (numbered.matches()) {
            String code = numbered.group(1).leftPad(2, '0');
            if (!STATE_NAMES.containsKey(code)) {
                return null;
            }
            String rest = numbered.group(2);
            return String.isBlank(rest) || codeForName(rest) == code ? code : null;
        }
        return codeForName(text);
    }

    /** The state's name as stored and printed, or null when it isn't a state. */
    public static String stateName(String text) {
        String code = stateCode(text);
        return code == null ? null : STATE_NAMES.get(code);
    }

    public static String stateNameForCode(String code) {
        return code == null ? null : STATE_NAMES.get(code);
    }

    private static String codeForName(String text) {
        if (stateKeys == null) {
            stateKeys = new Map<String, String>(STATE_ALIASES);
            for (String code : STATE_NAMES.keySet()) {
                if (!RETIRED_CODES.contains(code)) {
                    stateKeys.put(keyOf(STATE_NAMES.get(code)), code);
                }
            }
        }
        return stateKeys.get(keyOf(text));
    }

    private static String keyOf(String text) {
        return text.toLowerCase().replace('&', 'and').replaceAll('[^a-z]', '');
    }

    // ---- GSTIN --------------------------------------------------------------

    /** Upper case with no spaces, or null for a blank one. */
    public static String normalizeGstin(String gstin) {
        return String.isBlank(gstin) ? null : gstin.deleteWhitespace().toUpperCase();
    }

    /**
     * A real GSTIN: 2-digit state code, 10-character PAN, entity number, a
     * 14th character, and a check character worked out from the first 14
     * (the GSTN's mod-36 scheme), so a single mistyped character is caught.
     */
    public static Boolean isValidGstin(String gstin) {
        String value = normalizeGstin(gstin);
        if (value == null || !Pattern.matches('[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z][0-9A-Z][0-9A-Z]', value)) {
            return false;
        }
        return STATE_NAMES.containsKey(value.left(2)) && value.right(1) == checkCharacter(value.left(14));
    }

    @TestVisible
    private static String checkCharacter(String first14) {
        Integer total = 0;
        for (Integer i = 0; i < first14.length(); i++) {
            Integer product = GSTIN_CHARACTERS.indexOf(first14.substring(i, i + 1)) * (Math.mod(i, 2) == 0 ? 1 : 2);
            total += product / 36 + Math.mod(product, 36);
        }
        Integer check = Math.mod(36 - Math.mod(total, 36), 36);
        return GSTIN_CHARACTERS.substring(check, check + 1);
    }

    /** The state a valid GSTIN is registered in, or null. */
    public static String stateNameForGstin(String gstin) {
        return isValidGstin(gstin) ? STATE_NAMES.get(normalizeGstin(gstin).left(2)) : null;
    }

    // ---- rates and units ------------------------------------------------------

    public static Boolean isGstRate(Decimal rate) {
        if (rate == null) {
            return false;
        }
        for (Decimal valid : GST_RATES) {
            if (valid == rate) {
                return true;
            }
        }
        return false;
    }

    public static String gstRatesText() {
        List<String> rates = new List<String>();
        for (Decimal rate : GST_RATES) {
            rates.add(rateText(rate));
        }
        String last = rates.remove(rates.size() - 1);
        return String.join(rates, ', ') + ' or ' + last;
    }

    // 18.00 as "18" and 0.10 as "0.1" (stripTrailingZeros would print 40 as "4E+1").
    public static String rateText(Decimal rate) {
        String text = rate.toPlainString();
        if (text.contains('.')) {
            text = text.replaceAll('0+$', '').removeEnd('.');
        }
        return text;
    }

    /** Refuses any line whose GST rate isn't one that exists. */
    public static void requireGstRates(List<BillController.LineItemInput> lines) {
        if (lines == null) {
            return;
        }
        for (BillController.LineItemInput line : lines) {
            if (line.taxRatePercent != null && !isGstRate(line.taxRatePercent)) {
                throw new GstRulesException(
                    'GST ' + rateText(line.taxRatePercent) + '% on "' + line.description
                    + '" is not a GST rate. Use ' + gstRatesText() + '%.'
                );
            }
        }
    }

    // GST units as the GSTR-1 offline tool writes them.
    private static final Map<String, String> UQC_NAMES = new Map<String, String>{
        'BAG' => 'BAGS', 'BOX' => 'BOX', 'BTL' => 'BOTTLES', 'CAN' => 'CANS', 'CTN' => 'CARTONS', 'DOZ' => 'DOZENS',
        'DRM' => 'DRUMS', 'GMS' => 'GRAMMES', 'KGS' => 'KILOGRAMS', 'KME' => 'KILOMETRE', 'LTR' => 'LITRES',
        'MLT' => 'MILILITRE', 'MTR' => 'METERS', 'NOS' => 'NUMBERS', 'OTH' => 'OTHERS', 'PAC' => 'PACKS',
        'PCS' => 'PIECES', 'PRS' => 'PAIRS', 'ROL' => 'ROLLS', 'SET' => 'SETS', 'SQF' => 'SQUARE FEET',
        'SQM' => 'SQUARE METERS', 'TON' => 'TONNES', 'UNT' => 'UNITS'
    };

    /** "NOS-NUMBERS", as the GSTR-1 offline tool lists units; "OTH-OTHERS" for an unknown one. */
    public static String uqcLabel(String uqc) {
        String code = uqc != null && UQC_NAMES.containsKey(uqc) ? uqc : 'OTH';
        return code + '-' + UQC_NAMES.get(code);
    }

    /** An HSN/SAC for a service: SAC codes all begin with 99. */
    public static Boolean isServiceCode(String hsn) {
        return hsn != null && hsn.trim().startsWith('99');
    }

    /** The GST unit (UQC) for a unit as written on a part or line, or null if unknown. */
    public static String uqcFor(String unitLabel) {
        if (String.isBlank(unitLabel)) {
            return null;
        }
        return UNIT_ALIASES.get(unitLabel.toLowerCase().replaceAll('[^a-z]', ''));
    }
}
