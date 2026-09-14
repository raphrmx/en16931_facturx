import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_cii/en16931_cii.dart';
import 'package:en16931_facturx/src/pdf.dart';
import 'package:en16931_facturx/src/profile.dart';
import 'package:en16931_facturx/src/validator.dart';

/// [pdf] turned into a Factur-X document carrying [invoice].
///
/// This is the whole of what Factur-X is, in one call: the invoice is written
/// as CII, the XML is attached to the PDF under the name the specification
/// fixes, and the metadata says at which level. The PDF is what a person
/// reads and the XML is what a machine reads, and they say the same thing
/// because one was made from the other.
///
/// The level is read from BT-24 unless [profile] names one. Set it on the
/// invoice with [FacturxProfile.specificationIdentifier], so that what the
/// document claims and what the XML claims cannot drift apart.
///
/// Nothing is checked here. Call [validateFacturx] first: a hybrid document
/// whose XML is refused is worse than a plain PDF, because the receiver
/// believed it.
///
/// Throws [ArgumentError] when neither the invoice nor [profile] names a
/// level, and [FacturxPdfException] when the PDF cannot be extended.
Uint8List facturxPdf(
  Uint8List pdf,
  Invoice invoice, {
  FacturxProfile? profile,
}) {
  final level = profile ?? facturxProfileOf(invoice);
  if (level == null) {
    throw ArgumentError.value(
      invoice.specificationIdentifier,
      'invoice.specificationIdentifier',
      'Claims no Factur-X profile, and none was given',
    );
  }
  return attachFacturxXml(pdf, writeCii(invoice), profile: level);
}

/// The invoice [pdf] carries, or null when it carries none.
///
/// The XML is taken out of the document and read as CII. What the document
/// does not carry is left out rather than guessed at, so [validateFacturx]
/// tells you what the sender got wrong instead of the reader hiding it.
///
/// Throws [FacturxPdfException] when [pdf] is not a PDF, and
/// [CiiFormatException] when the attachment is not a readable invoice.
Invoice? readFacturxInvoice(Uint8List pdf) {
  final xml = readFacturxXml(pdf);
  return xml == null ? null : readCii(xml);
}
