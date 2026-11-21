import {
    STATE_OPTIONS,
    stateCode,
    stateName,
    searchStates,
    normalizeGstin,
    isValidGstin,
    stateNameForGstin,
    gstinProblem,
    checkGstinBox,
    withStateFromGstin,
    isGstRate,
    GST_RATE_TEXT,
    GST_RATE_OPTIONS,
    UNIT_OPTIONS,
    unitOptionsWith,
    todayIso,
    monthLabel,
    financialYearOf,
    isInFiledMonth,
    filedLockText,
    filedUpToOptions,
    gstPeriods,
    gstDueDates,
    shortDateLabel,
    capsFor,
    changedValue
} from 'c/gst';

// The same examples as GstRulesTest.cls, so screens and server agree.
const MP_GSTIN = '23AAACI7904G1ZV';
const MH_GSTIN = '27AAPFU0939F1ZV';

describe('c/gst', () => {
    describe('states', () => {
        it('understands the ways a state gets typed', () => {
            [
                'Madhya Pradesh', 'madhya pradesh', 'Madhyapradesh', 'MADHYA PRADESH ', 'MP', 'm.p.', 'Mp',
                '23', '23-Madhya Pradesh', '23 - MP', '23 Madhya Pradesh', '23. madhyapradesh'
            ].forEach((typed) => expect([typed, stateCode(typed)]).toEqual([typed, '23']));
            expect(stateCode('Jammu & Kashmir')).toBe('01');
            expect(stateCode('New Delhi')).toBe('07');
            expect(stateCode('Orissa')).toBe('21');
            expect(stateCode('TS')).toBe('36');
            expect(stateCode('Pondicherry')).toBe('34');
            expect(stateCode('Other Territory')).toBe('97');
        });

        it('refuses what is not a state', () => {
            ['Ujjain', 'Indore MP', '99', '00', '27-Madhya Pradesh', 'XYZ', '2 3', '', '  ', null, undefined].forEach((typed) =>
                expect([typed, stateCode(typed)]).toEqual([typed, null])
            );
        });

        it('retired codes only by number; their names mean the current code', () => {
            expect(stateCode('Daman and Diu')).toBe('26');
            expect(stateCode('Andhra Pradesh')).toBe('37');
            expect(stateCode('25')).toBe('25');
            expect(stateName('25')).toBe('Daman and Diu');
        });

        it('stores and prints the name', () => {
            expect(stateName('mp')).toBe('Madhya Pradesh');
            expect(stateName('DNH')).toBe('Dadra and Nagar Haveli and Daman and Diu');
            expect(stateName('Ujjain')).toBeNull();
        });

        it('offers every current state by name, in order, without the retired codes', () => {
            const names = STATE_OPTIONS.map((o) => o.value);
            expect(names).toHaveLength(37);
            expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)));
            expect(names).toContain('Madhya Pradesh');
            expect(names).not.toContain('Daman and Diu');
            expect(names).not.toContain('Andhra Pradesh (Old)');
            expect(STATE_OPTIONS[0]).toEqual({ label: 'Andaman and Nicobar Islands', value: 'Andaman and Nicobar Islands' });
        });

        it('search puts a matching abbreviation first, then names starting with the word', () => {
            expect(searchStates('mp')[0]).toBe('Madhya Pradesh');
            expect(searchStates('ma')).toEqual(expect.arrayContaining(['Madhya Pradesh', 'Maharashtra', 'Manipur']));
            expect(searchStates('ma').indexOf('Madhya Pradesh')).toBeLessThan(searchStates('ma').indexOf('Himachal Pradesh'));
            expect(searchStates('pradesh')).toEqual(expect.arrayContaining(['Uttar Pradesh', 'Madhya Pradesh']));
            expect(searchStates('', 5)).toHaveLength(5);
            expect(searchStates('zzz')).toEqual([]);
        });
    });

    describe('GSTIN', () => {
        it('checks the format, state code and check character', () => {
            expect(isValidGstin(MP_GSTIN)).toBe(true);
            expect(isValidGstin(MH_GSTIN)).toBe(true);
            expect(isValidGstin(' 27aapfu0939f1zv ')).toBe(true);

            expect(isValidGstin('27AAPFU0939F1ZW')).toBe(false);
            expect(isValidGstin('27AAPFU0938F1ZV')).toBe(false);
            expect(isValidGstin('27AAPUF0939F1ZV')).toBe(false);
            expect(isValidGstin('99AAPFU0939F1ZV')).toBe(false);
            expect(isValidGstin('27AAPFU0939F1Z')).toBe(false);
            expect(isValidGstin('27AAPFU0939F1ZVX')).toBe(false);
            expect(isValidGstin('27AAPFU0939F0ZV')).toBe(false);
            expect(isValidGstin('')).toBe(false);
            expect(isValidGstin(null)).toBe(false);
        });

        it('tidies and finds the state', () => {
            expect(normalizeGstin(' 23aaa ci7904g1zv ')).toBe(MP_GSTIN);
            expect(stateNameForGstin(MP_GSTIN)).toBe('Madhya Pradesh');
            expect(stateNameForGstin('23AAACI7904G1ZX')).toBeNull();
        });

        it('says what is wrong in plain words, and nothing for a blank or good one', () => {
            expect(gstinProblem('')).toBe('');
            expect(gstinProblem(MH_GSTIN)).toBe('');
            expect(gstinProblem('kjhsdj090')).toBe('A GSTIN has 15 characters; this has 9.');
            expect(gstinProblem('27AAPFU0939F1ZW')).toContain('not valid');
        });

        it('marks the box as soon as it is typed', () => {
            const box = { value: '27AAPFU0939F1ZW', setCustomValidity: jest.fn(), reportValidity: jest.fn() };
            checkGstinBox(box);
            expect(box.setCustomValidity).toHaveBeenCalledWith(expect.stringContaining('not valid'));
            expect(box.reportValidity).toHaveBeenCalled();

            box.value = MH_GSTIN;
            checkGstinBox(box);
            expect(box.setCustomValidity).toHaveBeenLastCalledWith('');
            expect(() => checkGstinBox(undefined)).not.toThrow();
        });

        it('fills a blank state from a valid GSTIN, never replacing one', () => {
            expect(withStateFromGstin({ gstin: MH_GSTIN, state: '' }).state).toBe('Maharashtra');
            expect(withStateFromGstin({ gstin: MH_GSTIN, state: 'Goa' }).state).toBe('Goa');
            expect(withStateFromGstin({ gstin: 'bad', state: '' }).state).toBe('');
        });
    });

    describe('rates and units', () => {
        it('knows the GST rates', () => {
            [0, '0', 0.25, 3, 5, '5.00', 12, 18, '18', 28, 40].forEach((rate) => expect([rate, isGstRate(rate)]).toEqual([rate, true]));
            [81, 17, '2', 100, -18, 18.5, '', null, undefined, 'abc'].forEach((rate) => expect([rate, isGstRate(rate)]).toEqual([rate, false]));
            expect(GST_RATE_TEXT.endsWith('28 or 40')).toBe(true);
            expect(GST_RATE_OPTIONS).toContainEqual({ label: '18%', value: '18' });
        });

        it('offers GST units, keeping a unit typed before the list existed', () => {
            expect(UNIT_OPTIONS[0]).toEqual({ label: 'NOS - Numbers', value: 'NOS' });
            expect(unitOptionsWith('PCS')).toBe(UNIT_OPTIONS);
            expect(unitOptionsWith('')).toBe(UNIT_OPTIONS);
            expect(unitOptionsWith('Set')[0]).toEqual({ label: 'Set', value: 'Set' });
        });
    });

    describe('financial years and filed months', () => {
        it('names months and financial years as bills do', () => {
            expect(todayIso(new Date(2026, 10, 5))).toBe('2026-11-05');
            expect(monthLabel('2026-10-31')).toBe('October 2026');
            expect(financialYearOf('2026-04-01')).toBe('2026-27');
            expect(financialYearOf('2026-03-31')).toBe('2025-26');
            expect(financialYearOf('2099-12-31')).toBe('2099-00');
        });

        it('locks a date on or before the filed month end, and nothing when nothing is filed', () => {
            expect(isInFiledMonth('2026-10-31', '2026-10-31')).toBe(true);
            expect(isInFiledMonth('2026-10-31', '2026-04-01')).toBe(true);
            expect(isInFiledMonth('2026-10-31', '2026-11-01')).toBe(false);
            expect(isInFiledMonth(null, '2026-04-01')).toBe(false);
            expect(isInFiledMonth('2026-10-31', null)).toBe(false);
            expect(filedLockText('2026-10-31')).toContain('filed up to October 2026');
        });

        it('offers months already over, newest first; quarter ends only for quarterly filers', () => {
            const today = new Date(2026, 10, 21);
            const monthly = filedUpToOptions('Monthly', today);
            expect(monthly[0]).toEqual({ label: 'Nothing filed yet', value: '' });
            expect(monthly[1]).toEqual({ label: 'October 2026', value: '2026-10-31' });
            expect(monthly[2].value).toBe('2026-09-30');
            expect(monthly.map((o) => o.value)).toContain('2026-02-28');
            expect(monthly).toHaveLength(19);

            const quarterly = filedUpToOptions('Quarterly', today).map((o) => o.value);
            expect(quarterly.slice(1, 4)).toEqual(['2026-09-30', '2026-06-30', '2026-03-31']);
            expect(quarterly).toHaveLength(9);
        });

        it('keeps offering an older saved month', () => {
            const options = filedUpToOptions('Monthly', new Date(2026, 10, 21), '2023-03-31');
            expect(options[options.length - 1]).toEqual({ label: 'March 2023', value: '2023-03-31' });
        });
    });

    describe('return periods', () => {
        it('months, newest first, the running one marked "so far"', () => {
            const periods = gstPeriods('Monthly', new Date(2026, 10, 21), 3);
            expect(periods.map((p) => p.label)).toEqual(['November 2026 (so far)', 'October 2026', 'September 2026']);
            expect(periods[1]).toEqual(expect.objectContaining({ start: '2026-10-01', end: '2026-10-31', value: '2026-10-01|2026-10-31', isOver: true }));
            expect(periods[0].isOver).toBe(false);
        });

        it('quarters follow the financial year, across a calendar year end', () => {
            const periods = gstPeriods('Quarterly', new Date(2027, 1, 10), 4);
            expect(periods.map((p) => p.label)).toEqual(['Jan-Mar 2027 (so far)', 'Oct-Dec 2026', 'Jul-Sep 2026', 'Apr-Jun 2026']);
            expect(periods[1]).toEqual(expect.objectContaining({ start: '2026-10-01', end: '2026-12-31' }));
            expect(periods[3]).toEqual(expect.objectContaining({ start: '2026-04-01', end: '2026-06-30' }));
        });

        it('a month or quarter ending today is still running', () => {
            expect(gstPeriods('Monthly', new Date(2026, 9, 31), 1)[0].isOver).toBe(false);
            expect(gstPeriods('Monthly', new Date(2026, 10, 1), 2)[1].isOver).toBe(true);
        });
    });
});

describe('gstDueDates (G5)', () => {
    const MONTHLY = { gstRegistrationType: 'Regular', gstFilingFrequency: 'Monthly', state: 'Madhya Pradesh' };
    const pick = (list) => list.map((d) => [d.form, d.period, d.due, d.daysLeft]);

    it('monthly: GSTR-1 by the 11th and GSTR-3B by the 20th, for each month after the filed one', () => {
        const due = gstDueDates({ ...MONTHLY, gstFiledUpTo: '2026-08-31' }, new Date(2026, 10, 21));
        expect(pick(due)).toEqual([
            ['GSTR-1', 'September 2026', '2026-10-11', -41],
            ['GSTR-3B', 'September 2026', '2026-10-20', -32],
            ['GSTR-1', 'October 2026', '2026-11-11', -10],
            ['GSTR-3B', 'October 2026', '2026-11-20', -1]
        ]);
        expect(due[3].text).toBe('GSTR-3B for October 2026: due 20 Nov 2026 (1 day late)');
        expect(due.every((d) => d.isLate && d.isSoon)).toBe(true);
    });

    it('with nothing marked filed, only the latest month that is over', () => {
        const due = gstDueDates(MONTHLY, new Date(2026, 11, 5));
        expect(pick(due)).toEqual([
            ['GSTR-1', 'November 2026', '2026-12-11', 6],
            ['GSTR-3B', 'November 2026', '2026-12-20', 15]
        ]);
        expect(due[0].isSoon).toBe(true);
        expect(due[1].isSoon).toBe(false);
        expect(due[0].text).toContain('(in 6 days)');
    });

    it('nothing when the last month that is over is filed', () => {
        expect(gstDueDates({ ...MONTHLY, gstFiledUpTo: '2026-10-31' }, new Date(2026, 10, 21))).toEqual([]);
    });

    it('quarterly: GSTR-1 by the 13th; GSTR-3B by the 22nd or the 24th, by state', () => {
        const today = new Date(2026, 9, 10);
        const mp = gstDueDates({ ...MONTHLY, gstFilingFrequency: 'Quarterly' }, today);
        expect(pick(mp)).toEqual([
            ['GSTR-1', 'Jul-Sep 2026', '2026-10-13', 3],
            ['GSTR-3B', 'Jul-Sep 2026', '2026-10-22', 12]
        ]);
        const delhi = gstDueDates({ ...MONTHLY, gstFilingFrequency: 'Quarterly', state: 'Delhi' }, today);
        expect(delhi[1].due).toBe('2026-10-24');
        // No state typed: the GSTIN's (27, Maharashtra: the 22nd).
        const byGstin = gstDueDates({ ...MONTHLY, gstFilingFrequency: 'Quarterly', state: '', gstin: '27AAPFU0939F1ZV' }, today);
        expect(byGstin[1].due).toBe('2026-10-22');
    });

    it('composition: CMP-08 by the 18th after the quarter; unregistered: nothing', () => {
        const due = gstDueDates({ gstRegistrationType: 'Composition', gstFilingFrequency: 'Monthly', state: 'MP' }, new Date(2026, 9, 18));
        expect(pick(due)).toEqual([['CMP-08', 'Jul-Sep 2026', '2026-10-18', 0]]);
        expect(due[0].text).toContain('(today)');
        expect(gstDueDates({ gstRegistrationType: 'Unregistered' }, new Date(2026, 9, 18))).toEqual([]);
        expect(gstDueDates(null)).toEqual([]);
    });

    it('a blank registration is regular, and a long gap shows at most six periods', () => {
        const due = gstDueDates({ gstFiledUpTo: '2025-01-31' }, new Date(2026, 10, 21));
        expect(due).toHaveLength(12);
        expect(due[0].period).toBe('May 2026');
        expect(due[11].period).toBe('October 2026');
    });

    it('shortDateLabel', () => {
        expect(shortDateLabel('2026-12-01')).toBe('1 Dec 2026');
    });
});

describe('capitals for vehicle numbers, GSTIN and IFSC', () => {
    const boxEvent = (field, value, detail) => ({ target: { value, dataset: { field } }, detail });

    it('a box kept in capitals gives capitals, whichever way the value comes', () => {
        expect(changedValue(boxEvent('registrationNumber', 'mp09ab1234'))).toBe('MP09AB1234');
        expect(changedValue(boxEvent('gstin', '', { value: '27aapfu0939f1zv' }))).toBe('27AAPFU0939F1ZV');
        ['chassisNumber', 'engineNumber', 'batteryNumber', 'bankIfsc'].forEach((field) => {
            expect(changedValue(boxEvent(field, 'ab12c'))).toBe('AB12C');
        });
    });

    it('other boxes are left as typed', () => {
        expect(changedValue(boxEvent('name', 'Ramesh Kumar'))).toBe('Ramesh Kumar');
        expect(changedValue(boxEvent('address', 'vijay nagar'))).toBe('vijay nagar');
        expect(changedValue({ target: { value: 'x' }, detail: { value: 'y' } })).toBe('y');
        expect(capsFor('gstin', null)).toBeNull();
        expect(capsFor('quantity', 2)).toBe(2);
    });
});
