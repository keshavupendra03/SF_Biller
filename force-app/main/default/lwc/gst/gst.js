/**
 * GST reference data and checks for the screens: the same lists and rules as
 * GstRules.cls, which has the final say when a record is saved. gst.test.js
 * and GstRulesTest check both against the same examples.
 */

// GST state codes. 25 and 28 are no longer given out and aren't offered,
// but an older GSTIN can still begin with them.
const STATE_NAMES = {
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman and Diu',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (Old)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory'
};
const RETIRED_CODES = ['25', '28'];

// Ways a state gets typed (lower case, letters only), beyond its own name.
const STATE_ALIASES = {
    jk: '01', hp: '02', pb: '03', ch: '04', uk: '05', ua: '05', uttaranchal: '05', hr: '06', dl: '07',
    newdelhi: '07', nctofdelhi: '07', delhinct: '07', rj: '08', up: '09', br: '10', sk: '11', ar: '12',
    nl: '13', mn: '14', mz: '15', tr: '16', ml: '17', as: '18', wb: '19', jh: '20', od: '21', or: '21',
    orissa: '21', cg: '22', ct: '22', chattisgarh: '22', mp: '23', gj: '24', dd: '26', dn: '26', dnh: '26',
    damananddiu: '26', dadraandnagarhaveli: '26', mh: '27', ka: '29', ga: '30', ld: '31', kl: '32',
    tn: '33', py: '34', pondicherry: '34', an: '35', andamanandnicobar: '35', ts: '36', tg: '36',
    ap: '37', la: '38'
};

const GSTIN_CHARACTERS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const GSTIN_FORMAT = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z][0-9A-Z][0-9A-Z]$/;

// Every rate in the GST schedules, including the September 2025 40% slab.
const GST_RATES = [0, 0.1, 0.25, 1, 1.5, 3, 5, 6, 7.5, 12, 18, 28, 40];

function codeOf(key) {
    return String(key).padStart(2, '0');
}

function keyOf(text) {
    return String(text).toLowerCase().replace(/&/g, 'and').replace(/[^a-z]/g, '');
}

const NAME_KEYS = Object.keys(STATE_NAMES).reduce(
    (keys, key) => {
        const code = codeOf(key);
        if (!RETIRED_CODES.includes(code)) {
            keys[keyOf(STATE_NAMES[key])] = code;
        }
        return keys;
    },
    { ...STATE_ALIASES }
);

function nameOf(code) {
    return STATE_NAMES[code] || null;
}

/** States to pick from, by name: the value stored and printed is the name. */
export const STATE_OPTIONS = Object.keys(STATE_NAMES)
    .map(codeOf)
    .filter((code) => !RETIRED_CODES.includes(code))
    .map((code) => ({ label: nameOf(code), value: nameOf(code), code }))
    .sort((a, b) => a.label.localeCompare(b.label))
    .map(({ label, value }) => ({ label, value }));

/**
 * The GST state code for however a state was typed: "Madhya Pradesh", "MP",
 * "m.p.", "23" or "23-Madhya Pradesh". Null when it isn't a state.
 */
export function stateCode(text) {
    if (!text || !String(text).trim()) {
        return null;
    }
    const numbered = String(text).trim().match(/^(\d{1,2})\s*[-.:)]?\s*(.*)$/);
    if (numbered) {
        const code = codeOf(numbered[1]);
        if (!nameOf(code)) {
            return null;
        }
        const rest = numbered[2];
        return !rest.trim() || NAME_KEYS[keyOf(rest)] === code ? code : null;
    }
    return NAME_KEYS[keyOf(text)] || null;
}

/** The state's name as stored and printed, or null when it isn't a state. */
export function stateName(text) {
    const code = stateCode(text);
    return code ? nameOf(code) : null;
}

/** Up to `limit` states for a typed word: an abbreviation first, then names starting with it. */
export function searchStates(term, limit = 8) {
    const typed = keyOf(term || '');
    const exact = stateName(term);
    const starting = [];
    const containing = [];
    STATE_OPTIONS.forEach(({ value }) => {
        const key = keyOf(value);
        if (value === exact) {
            return;
        }
        if (key.startsWith(typed)) {
            starting.push(value);
        } else if (typed && key.includes(typed)) {
            containing.push(value);
        }
    });
    return [...(exact ? [exact] : []), ...starting, ...containing].slice(0, limit);
}

/** Upper case with no spaces; empty for a blank one. */
export function normalizeGstin(gstin) {
    return (gstin || '').replace(/\s/g, '').toUpperCase();
}

function checkCharacter(first14) {
    let total = 0;
    for (let i = 0; i < first14.length; i++) {
        const product = GSTIN_CHARACTERS.indexOf(first14[i]) * (i % 2 === 0 ? 1 : 2);
        total += Math.floor(product / 36) + (product % 36);
    }
    return GSTIN_CHARACTERS[(36 - (total % 36)) % 36];
}

/** A real GSTIN: state code, PAN, entity number, and the right check character. */
export function isValidGstin(gstin) {
    const value = normalizeGstin(gstin);
    return GSTIN_FORMAT.test(value) && !!nameOf(value.slice(0, 2)) && value[14] === checkCharacter(value.slice(0, 14));
}

export function stateNameForGstin(gstin) {
    return isValidGstin(gstin) ? nameOf(normalizeGstin(gstin).slice(0, 2)) : null;
}

/** What's wrong with a typed GSTIN, or '' when it's fine or blank. */
export function gstinProblem(gstin) {
    const value = normalizeGstin(gstin);
    if (!value || isValidGstin(value)) {
        return '';
    }
    return value.length !== 15
        ? `A GSTIN has 15 characters; this has ${value.length}.`
        : 'This GSTIN is not valid. Check it on the GST certificate, or leave it blank.';
}

/** Shows a GSTIN problem on a lightning-input as soon as it's typed. */
export function checkGstinBox(input) {
    if (input && input.setCustomValidity) {
        input.setCustomValidity(gstinProblem(input.value));
        input.reportValidity();
    }
}

// Boxes (by data-field) whose codes are kept in capitals as they're typed:
// vehicle numbers, GSTIN, IFSC. The server stores them so too (UpperCaseText,
// GstPartyDetails), whatever a screen sends.
const CAPS_FIELDS = new Set(['registrationNumber', 'chassisNumber', 'engineNumber', 'batteryNumber', 'gstin', 'bankIfsc']);

/** The value in capitals if `field` is one kept in capitals. */
export function capsFor(field, value) {
    return CAPS_FIELDS.has(field) && typeof value === 'string' ? value.toUpperCase() : value;
}

/**
 * The value a form box changed to, in capitals for a box kept in capitals. A
 * lightning-combobox reports it in the event's detail; a lightning-input in
 * both; a test's plain event only on the box itself.
 */
export function changedValue(event) {
    const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    const field = event.target && event.target.dataset ? event.target.dataset.field : undefined;
    return capsFor(field, value);
}

/** The same details, with a state typed some other way ("MP") shown by its name. */
export function tidyState(details) {
    const name = stateName(details.state);
    return name ? { ...details, state: name } : details;
}

/** The same details, with a blank state filled from a valid GSTIN. */
export function withStateFromGstin(details) {
    if (details.state && String(details.state).trim()) {
        return details;
    }
    const state = stateNameForGstin(details.gstin);
    return state ? { ...details, state } : details;
}

export function isGstRate(rate) {
    if (rate === null || rate === undefined || String(rate).trim() === '') {
        return false;
    }
    const value = Number(rate);
    return GST_RATES.includes(value);
}

export const GST_RATE_TEXT = `${GST_RATES.slice(0, -1).join(', ')} or ${GST_RATES[GST_RATES.length - 1]}`;

export const GST_RATE_OPTIONS = GST_RATES.map((rate) => ({ label: `${rate}%`, value: String(rate) }));

// ---- financial years and filed months (dates as "yyyy-mm-dd") ---------------

const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function isoOf(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Today on this device, as "yyyy-mm-dd". */
export function todayIso(today = new Date()) {
    return isoOf(today);
}

/** "October 2026" for "2026-10-31". */
export function monthLabel(iso) {
    const [year, month] = iso.split('-').map(Number);
    return `${MONTH_NAMES[month - 1]} ${year}`;
}

/** The Indian financial year a date is in, as invoice numbers show it: "2026-27". */
export function financialYearOf(iso) {
    const [year, month] = iso.split('-').map(Number);
    const start = month >= 4 ? year : year - 1;
    return `${start}-${String((start + 1) % 100).padStart(2, '0')}`;
}

/** Whether a bill dated `dateIso` is in a month whose GST returns are filed. */
export function isInFiledMonth(filedUpTo, dateIso) {
    return !!filedUpTo && !!dateIso && dateIso <= filedUpTo;
}

export function filedLockText(filedUpTo) {
    return `GST returns are filed up to ${monthLabel(filedUpTo)}, so bills dated up to then can't be added, changed or deleted.`;
}

/**
 * Months that can be marked as filed, newest first: ones already over, only
 * quarter ends for quarterly filers, plus the saved one if it's older.
 */
export function filedUpToOptions(frequency, today = new Date(), saved = '') {
    const quarterly = frequency === 'Quarterly';
    const wanted = quarterly ? 8 : 18;
    const months = [];
    for (let back = 1; months.length < wanted; back++) {
        // Day 0 of a month is the last day of the month before it.
        const end = new Date(today.getFullYear(), today.getMonth() - back + 1, 0);
        if (!quarterly || (end.getMonth() + 1) % 3 === 0) {
            months.push(isoOf(end));
        }
    }
    if (saved && !months.includes(saved)) {
        months.push(saved);
    }
    return [{ label: 'Nothing filed yet', value: '' }, ...months.map((iso) => ({ label: monthLabel(iso), value: iso }))];
}

const SHORT_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * Return periods to pick from, newest first: months, or quarters (Apr-Jun,
 * Jul-Sep, Oct-Dec, Jan-Mar) for quarterly filers. The one still running is
 * included, marked "so far". Each: { label, value: 'start|end', start, end, isOver }.
 */
export function gstPeriods(frequency, today = new Date(), count = 12) {
    const quarterly = frequency === 'Quarterly';
    const periods = [];
    // The period today is in: its first month.
    let year = today.getFullYear();
    let month = today.getMonth();
    if (quarterly) {
        month -= (month + 12 - 3) % 3;
    }
    const todayText = isoOf(today);
    while (periods.length < count) {
        const startDate = new Date(year, month, 1);
        const endDate = new Date(year, month + (quarterly ? 3 : 1), 0);
        const start = isoOf(startDate);
        const end = isoOf(endDate);
        const isOver = end < todayText;
        const name = quarterly
            ? `${SHORT_MONTHS[startDate.getMonth()]}-${SHORT_MONTHS[endDate.getMonth()]} ${endDate.getFullYear()}`
            : monthLabel(start);
        periods.push({ label: isOver ? name : `${name} (so far)`, value: `${start}|${end}`, start, end, isOver });
        month -= quarterly ? 3 : 1;
        if (month < 0) {
            month += 12;
            year -= 1;
        }
    }
    return periods;
}

// ---- return due dates (G5) ---------------------------------------------------
// The usual dates, as on 2026-11-21. The government sometimes extends one by
// notification; the screens say so.

// Quarterly GSTR-3B is due on the 22nd for these states and UTs, the 24th for the rest.
const EARLY_QUARTERLY_3B = new Set(['22', '23', '24', '26', '27', '29', '30', '31', '32', '33', '34', '35', '36', '37']);
const REMIND_DAYS = 7;
const MAX_PERIODS = 6;

function dayOfMonthAfter(periodEnd, day) {
    const [year, month] = periodEnd.split('-').map(Number);
    // month is 1-based, so this is the month after the period's last month.
    return isoOf(new Date(year, month, day));
}

function daysBetween(fromIso, toIso) {
    const [fy, fm, fd] = fromIso.split('-').map(Number);
    const [ty, tm, td] = toIso.split('-').map(Number);
    return Math.round((Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / 86400000);
}

/** "11 Dec 2026" for "2026-12-11". */
export function shortDateLabel(iso) {
    const [year, month, day] = iso.split('-').map(Number);
    return `${day} ${SHORT_MONTHS[month - 1]} ${year}`;
}

function whenText(daysLeft) {
    if (daysLeft === 0) {
        return 'today';
    }
    if (daysLeft > 0) {
        return daysLeft === 1 ? 'tomorrow' : `in ${daysLeft} days`;
    }
    return daysLeft === -1 ? '1 day late' : `${-daysLeft} days late`;
}

/**
 * The returns a company still has to file, oldest first: for each period
 * that is over and after its "filed up to" month (or, with nothing marked
 * filed, just the latest one), each form with its due date.
 *   Regular, monthly:    GSTR-1 by the 11th, GSTR-3B by the 20th of the next month.
 *   Regular, quarterly:  GSTR-1 by the 13th, GSTR-3B by the 22nd or 24th after the quarter.
 *   Composition:         CMP-08 by the 18th after the quarter.
 *   Unregistered:        nothing.
 * Each: { key, form, period, due, dueLabel, daysLeft, isLate, isSoon, text }.
 */
export function gstDueDates(profile, today = new Date()) {
    const type = (profile && profile.gstRegistrationType) || 'Regular';
    if (!profile || type === 'Unregistered') {
        return [];
    }
    const composition = type === 'Composition';
    const quarterly = composition || profile.gstFilingFrequency === 'Quarterly';
    const filedUpTo = profile.gstFiledUpTo || '';
    let over = gstPeriods(quarterly ? 'Quarterly' : 'Monthly', today, MAX_PERIODS + 1).filter((p) => p.isOver);
    over = filedUpTo ? over.filter((p) => p.end > filedUpTo) : over.slice(0, 1);
    const state = stateCode(profile.state) || (isValidGstin(profile.gstin) ? normalizeGstin(profile.gstin).slice(0, 2) : null);
    const todayText = isoOf(today);

    const forms = [];
    if (composition) {
        forms.push(['CMP-08', 18]);
    } else if (quarterly) {
        forms.push(['GSTR-1', 13], ['GSTR-3B', state && !EARLY_QUARTERLY_3B.has(state) ? 24 : 22]);
    } else {
        forms.push(['GSTR-1', 11], ['GSTR-3B', 20]);
    }

    const due = [];
    over.slice(0, MAX_PERIODS).reverse().forEach((period) => {
        const name = period.label;
        forms.forEach(([form, day]) => {
            const dueIso = dayOfMonthAfter(period.end, day);
            const daysLeft = daysBetween(todayText, dueIso);
            due.push({
                key: `${form}-${period.end}`,
                form,
                period: name,
                due: dueIso,
                dueLabel: shortDateLabel(dueIso),
                daysLeft,
                isLate: daysLeft < 0,
                isSoon: daysLeft <= REMIND_DAYS,
                text: `${form} for ${name}: due ${shortDateLabel(dueIso)} (${whenText(daysLeft)})`
            });
        });
    });
    return due;
}

// GST units (UQC): the ones a workshop uses most, first.
export const UNIT_OPTIONS = [
    ['NOS', 'Numbers'], ['PCS', 'Pieces'], ['SET', 'Sets'], ['PRS', 'Pairs'], ['LTR', 'Litres'],
    ['MLT', 'Millilitres'], ['KGS', 'Kilograms'], ['GMS', 'Grams'], ['MTR', 'Metres'], ['BOX', 'Box'],
    ['BTL', 'Bottles'], ['CAN', 'Cans'], ['PAC', 'Packs'], ['ROL', 'Rolls'], ['DOZ', 'Dozens'],
    ['UNT', 'Units'], ['SQF', 'Square feet'], ['SQM', 'Square metres'], ['BAG', 'Bags'], ['OTH', 'Others']
].map(([value, name]) => ({ label: `${value} - ${name}`, value }));

/**
 * Unit options for a box already holding `current`: a unit typed before this
 * list existed stays offered, so opening a part doesn't lose it.
 */
export function unitOptionsWith(current) {
    if (!current || UNIT_OPTIONS.some((option) => option.value === current)) {
        return UNIT_OPTIONS;
    }
    return [{ label: current, value: current }, ...UNIT_OPTIONS];
}
