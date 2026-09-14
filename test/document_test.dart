import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

import 'pdf_test.dart' show minimalPdf;

Invoice _invoice(FacturxProfile profile) => Invoice.fromLines(
      number: '2026-0042',
      issueDate: DateTime(2026, 9, 14),
      dueDate: DateTime(2026, 10, 14),
      specificationIdentifier: profile.specificationIdentifier,
      buyerReference: 'CMD-778',
      seller: const Seller(
        name: 'COMAPPS SARL',
        vatIdentifier: 'FR12345678901',
        address: Address(city: 'Paris', postalCode: '75001', country: 'FR'),
      ),
      buyer: const Buyer(
        name: 'Client SA',
        address: Address(city: 'Lyon', postalCode: '69001', country: 'FR'),
      ),
      lines: [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Conseil'),
          quantity: 8,
          unitPrice: 150.00,
          vatRate: 20,
          unit: UnitCode.hour,
        ),
      ],
    );

void main() {
  test('the PDF and the XML say the same thing, because one made the other',
      () {
    final invoice = _invoice(FacturxProfile.en16931);
    expect(validateFacturx(invoice), isEmpty);

    final document = facturxPdf(minimalPdf(), invoice);
    final read = readFacturxInvoice(document);

    expect(read, isNotNull);
    expect(read!.number, '2026-0042');
    expect(read.totals.amountDueForPayment, invoice.totals.amountDueForPayment);
    expect(facturxProfileOf(read), FacturxProfile.en16931);
    expect(validateFacturx(read), isEmpty);
  });

  test('the level the document claims is the level the XML claims', () {
    for (final profile in [
      FacturxProfile.basic,
      FacturxProfile.en16931,
      FacturxProfile.extended,
    ]) {
      final document = facturxPdf(minimalPdf(), _invoice(profile));
      expect(
        readFacturxInvoice(document)!.specificationIdentifier,
        profile.specificationIdentifier,
        reason: profile.name,
      );
    }
  });

  test('a plain PDF carries no invoice', () {
    expect(readFacturxInvoice(minimalPdf()), isNull);
  });

  test('an invoice claiming no level is not written at a guess', () {
    final invoice = Invoice.fromLines(
      number: '1',
      issueDate: DateTime(2026, 9, 14),
      specificationIdentifier: null,
      seller: const Seller(
        name: 'COMAPPS SARL',
        address: Address(city: 'Paris', postalCode: '75001', country: 'FR'),
      ),
      buyer: const Buyer(
        name: 'Client SA',
        address: Address(city: 'Lyon', postalCode: '69001', country: 'FR'),
      ),
      lines: [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Conseil'),
          quantity: 1,
          unitPrice: 10,
          vatRate: 20,
        ),
      ],
    );
    expect(() => facturxPdf(minimalPdf(), invoice), throwsArgumentError);
    expect(
      facturxPdf(minimalPdf(), invoice, profile: FacturxProfile.basic),
      isA<Uint8List>(),
    );
  });
}
