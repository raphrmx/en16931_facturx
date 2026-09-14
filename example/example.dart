// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/en16931_facturx.dart';

/// Builds a French invoice, checks it at its level, and turns a PDF into the
/// hybrid document that carries the invoice twice: once for a reader and once
/// for a machine.
void main() {
  final invoice = Invoice.fromLines(
    number: '2026-0042',
    issueDate: DateTime(2026, 9, 14),
    dueDate: DateTime(2026, 10, 14),
    specificationIdentifier: FacturxProfile.en16931.specificationIdentifier,
    buyerReference: 'CMD-778',
    seller: const Seller(
      name: 'COMAPPS SARL',
      vatIdentifier: 'FR12345678901',
      address: Address(
        line1: '1 rue de Rivoli',
        city: 'Paris',
        postalCode: '75001',
        country: 'FR',
      ),
    ),
    buyer: const Buyer(
      name: 'Client SA',
      address: Address(
        line1: '2 place Bellecour',
        city: 'Lyon',
        postalCode: '69001',
        country: 'FR',
      ),
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

  final violations = validateFacturx(invoice);
  print(violations.isEmpty ? 'the invoice holds up' : 'not yet:');
  for (final violation in violations) {
    print('  $violation');
  }

  // In an application this is the PDF that was drawn for the buyer to read.
  final document = facturxPdf(_aPdf(), invoice);
  print('the document is ${document.length} bytes');
  print('  PDF/A: ${pdfaConformance(document) ?? 'not claimed'}');

  // What a receiver does with it.
  final received = readFacturxInvoice(document)!;
  print(
    '  read back ${received.number} at '
    '${facturxProfileOf(received)!.name}, '
    '${received.totals.amountDueForPayment} ${received.currency} due',
  );
}

/// A one page PDF, so the example runs without a file beside it.
Uint8List _aPdf() {
  const page = 'BT /F1 24 Tf 72 760 Td (Facture 2026-0042) Tj ET';
  const pageDictionary =
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 595 842] /Contents 4 0 R '
      '/Resources << /Font << /F1 5 0 R >> >> >>';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    pageDictionary,
    '<< /Length ${page.length} >>\nstream\n$page\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n$object\nendobj\n');
  }
  final start = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$start\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}
