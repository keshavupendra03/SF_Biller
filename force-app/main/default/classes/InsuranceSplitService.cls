/**
 * Splits an insurance claim job into the insurer's lines and the customer's
 * (architecture.md §D.1, G6). Each line says what percent the insurer pays
 * (metal parts 100, plastic and rubber 50 after depreciation, labour 100);
 * the customer pays the rest, plus the policy's compulsory excess, which comes
 * off the insurer's share.
 *
 * Both bills keep every line's full quantity and price; the other side's
 * share goes in as the line's discount, so each bill's taxable value is its
 * own share and the two add up to the job exactly, line by line. The excess
 * is a GST-inclusive amount, taken off the insurer's lines in proportion to
 * what each costs the insurer, so every line keeps its own GST rate.
 */
public with sharing class InsuranceSplitService {

    public class InsuranceSplitException extends Exception {}

    public class Split {
        public List<BillController.LineItemInput> insurerLines = new List<BillController.LineItemInput>();
        public List<BillController.LineItemInput> customerLines = new List<BillController.LineItemInput>();
    }

    public static Split split(List<BillController.LineItemInput> lines, List<Decimal> insurerPercents, Decimal compulsoryExcess) {
        Decimal excess = compulsoryExcess == null ? 0 : compulsoryExcess;
        if (excess < 0) {
            throw new InsuranceSplitException('The compulsory excess can\'t be less than zero.');
        }

        List<Decimal> gross = new List<Decimal>();
        List<Decimal> insurerTaxable = new List<Decimal>();
        Decimal insurerTotal = 0;
        for (Integer i = 0; i < lines.size(); i++) {
            BillController.LineItemInput line = lines[i];
            Decimal percent = insurerPercents[i] == null ? 100 : insurerPercents[i];
            if (percent < 0 || percent > 100) {
                throw new InsuranceSplitException('The insurance share on "' + line.description + '" must be between 0 and 100%.');
            }
            Decimal lineGross = line.quantity * line.unitPrice;
            Decimal value = lineGross - (line.discount == null ? 0 : line.discount);
            Decimal share = GstCalculatorService.round2(value * percent / 100);
            gross.add(lineGross);
            insurerTaxable.add(share);
            insurerTotal += share * (1 + rateOf(line) / 100);
        }

        if (excess > 0) {
            if (excess > GstCalculatorService.round2(insurerTotal)) {
                throw new InsuranceSplitException('The compulsory excess (Rs. ' + excess.setScale(2) + ') is more than the insurance company\'s share (Rs. '
                    + GstCalculatorService.round2(insurerTotal) + ').');
            }
            // The excess, with its GST, comes off each line in proportion to
            // what the line costs the insurer: in taxable terms, excess x share / total.
            for (Integer i = 0; i < lines.size(); i++) {
                insurerTaxable[i] -= GstCalculatorService.round2(excess * insurerTaxable[i] / insurerTotal);
            }
        }

        Split result = new Split();
        for (Integer i = 0; i < lines.size(); i++) {
            BillController.LineItemInput line = lines[i];
            Decimal value = gross[i] - (line.discount == null ? 0 : line.discount);
            Decimal customerTaxable = value - insurerTaxable[i];
            if (insurerTaxable[i] > 0) {
                BillController.LineItemInput insurerLine = copy(line, gross[i] - insurerTaxable[i]);
                result.insurerLines.add(insurerLine);
            }
            if (customerTaxable > 0) {
                BillController.LineItemInput customerLine = copy(line, gross[i] - customerTaxable);
                // Its goods are on the insurer's bill, which takes the stock.
                customerLine.partId = null;
                result.customerLines.add(customerLine);
            }
        }
        if (result.insurerLines.isEmpty()) {
            throw new InsuranceSplitException('The insurance company pays nothing on these lines: turn the split off and bill the customer.');
        }
        if (result.customerLines.isEmpty()) {
            throw new InsuranceSplitException('The customer pays nothing: turn the split off and bill the insurance company.');
        }
        return result;
    }

    private static Decimal rateOf(BillController.LineItemInput line) {
        return line.taxRatePercent == null ? 0 : line.taxRatePercent;
    }

    private static BillController.LineItemInput copy(BillController.LineItemInput line, Decimal discount) {
        BillController.LineItemInput copy = new BillController.LineItemInput();
        copy.partId = line.partId;
        copy.description = line.description;
        copy.quantity = line.quantity;
        copy.unitPrice = line.unitPrice;
        copy.taxRatePercent = line.taxRatePercent;
        copy.gstType = line.gstType;
        copy.hsnSacCode = line.hsnSacCode;
        copy.unitLabel = line.unitLabel;
        copy.discount = discount;
        return copy;
    }
}
