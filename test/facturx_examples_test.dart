import 'dart:io';

import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

/// One example document at each of the five levels, and one hybrid PDF.
///
/// They are not part of this repository. Run
/// `dart run tool/fetch_examples.dart` to pull them in, and these tests wake
/// up. Checking our own invoices proves the levels do what this package
/// thinks they do; checking these proves they do what Factur-X thinks they
/// do.
const String _directory = 'examples_from_facturx';

/// Which level each document is issued at.
const Map<String, FacturxProfile> _levels = {
  'minimum.xml': FacturxProfile.minimum,
  'basicwl.xml': FacturxProfile.basicWl,
  'basic.xml': FacturxProfile.basic,
  'en16931.xml': FacturxProfile.en16931,
  'extended.xml': FacturxProfile.extended,
};

void main() {
  final directory = Directory(_directory);
  if (!directory.existsSync()) {
    test('the published examples', () {}, skip: 'Run tool/fetch_examples.dart');
    return;
  }

  for (final entry in _levels.entries) {
    final file = File('$_directory/${entry.key}');
    if (!file.existsSync()) continue;

    group(entry.key, () {
      late Invoice invoice;

      setUp(() {
        invoice = readCii(file.readAsStringSync());
      });

      test('claims the level it is filed under', () {
        expect(facturxProfileOf(invoice), entry.value);
      });

      test('breaks no rule that would refuse it', () {
        // These are the documents Factur-X publishes as examples of its own
        // levels. A fatal violation means this package reads or checks
        // something wrong, not that the document is wrong.
        expect(
          validateFacturx(invoice)
              .where((v) => v.rule.severity == RuleSeverity.fatal)
              .map((violation) => violation.toString()),
          isEmpty,
        );
      });

      test('is refused at a level that asks for more than it carries', () {
        // A level below EN 16931 leaves terms out that a higher one needs, so
        // the same document checked as something bigger has to fail. This is
        // what makes the subsets real rather than decorative.
        if (entry.value != FacturxProfile.minimum) return;
        expect(
          validateFacturx(
            invoice,
            profile: FacturxProfile.basic,
          ).map((violation) => violation.rule.id),
          contains('BR-16'),
        );
      });
    });
  }

  group('a real hybrid document', () {
    final pdf = File('$_directory/hybrid.pdf');

    test('gives up the invoice it carries', () {
      final bytes = pdf.readAsBytesSync();
      expect(isFacturxPdf(bytes), isTrue);
      expect(pdfaConformance(bytes), '3B');

      final invoice = readFacturxInvoice(bytes);
      expect(invoice, isNotNull);
      expect(invoice!.number, isNotEmpty);
      expect(facturxProfileOf(invoice), FacturxProfile.en16931);
      expect(
        validateFacturx(invoice)
            .where((v) => v.rule.severity == RuleSeverity.fatal)
            .map((violation) => violation.toString()),
        isEmpty,
      );
    });
  });
}
