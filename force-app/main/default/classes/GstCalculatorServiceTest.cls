/**
 * Runs every vector in shared/contracts/test_vectors.json (deployed as the
 * GstTestVectors static resource) through GstCalculatorService's
 * intra-state path — this file is unchanged from the reference project,
 * exercising calculateLine(input)/calculateBill(inputs) without a
 * SupplyType, which default to INTRA_STATE and so exactly match this
 * project's new, IGST-aware class on the original CGST+SGST-only contract.
 */
@isTest
private class GstCalculatorServiceTest {

    private class VectorsFile {
        List<LineVector> lineVectors;
        List<BillVector> billVectors;
    }

    private class LineVector {
        String name;
        LineInput input;
        LineExpected expected;
    }

    private class LineInput {
        Decimal quantity;
        Decimal unitPrice;
        Decimal taxRatePercent;
    }

    private class LineExpected {
        Decimal subtotal;
        Decimal cgst;
        Decimal sgst;
        Decimal gst;
        Decimal total;
    }

    private class BillVector {
        String name;
        BillInput input;
        BillExpected expected;
    }

    private class BillInput {
        List<LineInput> lines;
    }

    private class BillExpected {
        Decimal subtotal;
        Decimal cgst;
        Decimal sgst;
        Decimal gst;
        Decimal grandTotal;
    }

    @isTest
    static void everySharedTestVectorMatches() {
        StaticResource sr = [
            SELECT Body FROM StaticResource WHERE Name = 'GstTestVectors' LIMIT 1
        ];
        VectorsFile vectors = (VectorsFile) JSON.deserialize(
            sr.Body.toString(),
            VectorsFile.class
        );

        System.assert(!vectors.lineVectors.isEmpty(), 'Expected at least one line vector.');
        System.assert(!vectors.billVectors.isEmpty(), 'Expected at least one bill vector.');

        Test.startTest();

        Integer checked = 0;
        for (LineVector v : vectors.lineVectors) {
            GstCalculatorService.GstLineItemInput input = new GstCalculatorService.GstLineItemInput(
                v.name,
                v.input.quantity,
                v.input.unitPrice,
                v.input.taxRatePercent
            );
            GstCalculatorService.GstLineResult result = GstCalculatorService.calculateLine(input);

            System.assertEquals(v.expected.subtotal, result.subtotal, v.name + ': subtotal');
            System.assertEquals(v.expected.cgst, result.cgst, v.name + ': cgst');
            System.assertEquals(v.expected.sgst, result.sgst, v.name + ': sgst');
            System.assertEquals(v.expected.gst, result.gst, v.name + ': gst');
            System.assertEquals(v.expected.total, result.total, v.name + ': total');
            checked++;
        }

        for (BillVector v : vectors.billVectors) {
            List<GstCalculatorService.GstLineItemInput> inputs = new List<GstCalculatorService.GstLineItemInput>();
            for (LineInput li : v.input.lines) {
                inputs.add(new GstCalculatorService.GstLineItemInput(
                    v.name,
                    li.quantity,
                    li.unitPrice,
                    li.taxRatePercent
                ));
            }
            GstCalculatorService.GstBillResult result = GstCalculatorService.calculateBill(inputs);

            System.assertEquals(v.expected.subtotal, result.subtotal, v.name + ': subtotal');
            System.assertEquals(v.expected.cgst, result.cgst, v.name + ': cgst');
            System.assertEquals(v.expected.sgst, result.sgst, v.name + ': sgst');
            System.assertEquals(v.expected.gst, result.gst, v.name + ': gst');
            System.assertEquals(v.expected.grandTotal, result.grandTotal, v.name + ': grandTotal');
            checked++;
        }

        Test.stopTest();

        // Guards against a silently-empty or partially-parsed vectors file
        // making this test pass by having nothing to check — update this
        // count deliberately if test_vectors.json gains/loses vectors.
        System.assertEquals(
            9,
            checked,
            'Expected exactly 9 vectors (4 line + 5 bill) to have been checked.'
        );
    }
}
