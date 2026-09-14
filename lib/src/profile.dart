import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/src/catalogue.g.dart';

/// One of the five levels a Factur-X invoice is issued at.
///
/// The levels are nested: each carries everything the one before it carries
/// and more. What changes with the level is how much of the invoice the
/// document holds, and therefore how much of the standard applies to it.
///
/// The level is not a quality ranking. France accepts [minimum] for tax
/// reporting, where the PDF is the invoice and the XML says only who, when
/// and how much. An invoice at that level has no lines at all, which is why
/// holding it to the whole standard would refuse a document that is perfectly
/// in order.
enum FacturxProfile {
  /// Who, when, how much. No lines, no VAT breakdown.
  minimum('minimum', 'MINIMUM'),

  /// The invoice without its lines: parties, totals, VAT breakdown, payment.
  basicWl('basicWl', 'BASIC WL'),

  /// The lines as well, at the level most invoices need.
  basic('basic', 'BASIC'),

  /// Everything EN 16931 asks for, and nothing beyond it.
  en16931('en16931', 'EN 16931'),

  /// Beyond the standard: terms France adds, and looser totals.
  extended('extended', 'EXTENDED');

  const FacturxProfile(this.key, this.conformanceLevel);

  /// What the catalogue calls this level.
  final String key;

  /// What the PDF metadata calls this level.
  ///
  /// The spelling is the specification's, spaces included, and a reader
  /// matches it exactly.
  final String conformanceLevel;

  /// BT-24 as this package writes it.
  String get specificationIdentifier => identifiers.first;

  /// Every BT-24 that claims this level, the ZUGFeRD spelling included.
  ///
  /// Germany writes the same document under its own identifier, so a reader
  /// that accepts only the Factur-X one refuses half of what arrives.
  List<String> get identifiers => facturxProfileIdentifiers[key]!;

  /// The rules this level asserts, of the standard and of Factur-X both.
  Set<String> get rules => facturxProfileRules[key]!;

  /// The rules this level puts on the document rather than on the invoice.
  Set<String> get syntaxRules => facturxSyntaxRules[key]!;

  /// The level [identifier] claims, or null when it claims none of them.
  static FacturxProfile? of(String? identifier) {
    if (identifier == null) return null;
    for (final profile in values) {
      if (profile.identifiers.contains(identifier)) return profile;
    }
    return null;
  }
}

/// The level [invoice] claims in BT-24, or null when it claims none.
///
/// Null is the answer for an invoice that is not Factur-X at all. It is also
/// the answer for one claiming a profile of some other flavour, XRechnung for
/// instance, which rides on the same syntax under its own identifier.
FacturxProfile? facturxProfileOf(Invoice invoice) =>
    FacturxProfile.of(invoice.specificationIdentifier);
