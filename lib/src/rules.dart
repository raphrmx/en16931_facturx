import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';

/// Checks one Factur-X rule against an invoice.
typedef FacturxCheck =
    Iterable<RuleViolation> Function(Invoice invoice, RuleDescriptor rule);

/// One cent, which is what EXTENDED allows per amount that went into a total.
final Decimal _cent = Decimal.parse('0.01');

/// Which VAT category each BR-FXEXT family stands for.
const Map<String, VatCategory> _categories = {
  'S': VatCategory.standardRate,
  'Z': VatCategory.zeroRated,
  'E': VatCategory.exempt,
  'AE': VatCategory.reverseCharge,
  'IC': VatCategory.intraCommunitySupply,
  'G': VatCategory.exportOutsideEu,
  'O': VatCategory.outsideScope,
  'AF': VatCategory.canaryIslands,
  'AG': VatCategory.ceutaAndMelilla,
};

/// The categories whose breakdown is grouped by rate as well as by category.
///
/// The others carry one entry for the whole category, because an invoice
/// cannot charge two different rates of nothing.
const Set<VatCategory> _byRate = {
  VatCategory.standardRate,
  VatCategory.canaryIslands,
  VatCategory.ceutaAndMelilla,
};

/// The rules of the standard this package evaluates, indexed by identifier.
final Map<String, RuleCheck> _standard = {
  ...presenceRules,
  ...conditionRules,
  ...decimalRules,
  ...codeListRules,
  ...vatCategoryRules,
};

/// The rules Factur-X states itself, as against the ones it borrows whole
/// from EN 16931.
///
/// A profile runs the ones its own level asserts, which
/// [FacturxProfile.rules] names. Nothing here runs for a profile that does
/// not ask for it.
final Map<String, FacturxCheck> facturxRules = {
  'BR-CO-25': _co25,
  'BR-FXEXT-01': _fxext01,
  'BR-FXEXT-CO-10': _co10,
  'BR-FXEXT-CO-11': _co11,
  'BR-FXEXT-CO-12': _co12,
  'BR-FXEXT-CO-13': _co13,
  'BR-FXEXT-CO-15': _co15,
  'BR-FXEXT-S-09b': _s09b,
  for (final entry in _standsFor.entries) entry.key: _borrow(entry.value),
  for (final entry in _categories.entries)
    'BR-FXEXT-${entry.key}-08ini': _breakdown(entry.value),
};

/// A rule EXTENDED restates to widen it with a term EN 16931 does not have.
///
/// The widening is empty on this model: there is no logistics service fee, no
/// item subtype, no non-VAT tax code. What is left is the rule of the
/// standard, so that is what runs, reported under the identifier Factur-X
/// gives it.
const Map<String, String> _standsFor = {
  'BR-FXEXT-BR-22': 'BR-22',
  'BR-FXEXT-BR-23': 'BR-23',
  'BR-FXEXT-BR-24': 'BR-24',
  'BR-FXEXT-BR-26': 'BR-26',
  'BR-FXEXT-BR-38': 'BR-38',
  'BR-FXEXT-BR-44': 'BR-44',
  'BR-FXEXT-BR-54-1': 'BR-54',
  'BR-FXEXT-BR-54-2': 'BR-54',
  'BR-FXEXT-CO-04': 'BR-CO-04',
  'BR-FXEXT-CO-16': 'BR-CO-16',
  'BR-FXEXT-S-01': 'BR-S-01',
  'BR-FXEXT-Z-01': 'BR-Z-01',
  'BR-FXEXT-E-01': 'BR-E-01',
  'BR-FXEXT-AE-01': 'BR-AE-01',
  'BR-FXEXT-IC-01': 'BR-IC-01',
  'BR-FXEXT-G-01': 'BR-G-01',
  'BR-FXEXT-O-01': 'BR-O-01',
  'BR-FXEXT-AF-01': 'BR-AF-01',
  'BR-FXEXT-AG-01': 'BR-AG-01',
};

/// The rules that say nothing more than another rule does, on this model.
///
/// Factur-X states each VAT breakdown rule three times: once counting the
/// lines alone, once also matching the exemption reasons carried per line,
/// and once saying either will do. EN 16931 has no exemption reason on a
/// line, so all three come to the same check, and running it three times
/// would report one mistake three times.
final Map<String, String> facturxSubsumed = {
  for (final family in _categories.keys) ...{
    'BR-FXEXT-$family-08rev': 'BR-FXEXT-$family-08ini',
    if (family == 'S')
      'BR-FXEXT-S08b': 'BR-FXEXT-S-08ini'
    else
      'BR-FXEXT-$family-08b': 'BR-FXEXT-$family-08ini',
  },
};

/// The rules an invoice built with this model cannot break.
///
/// They bear on the terms EXTENDED adds and EN 16931 does not have: a coded
/// free text beside the written one, a parent line, an item subtype, a party
/// the standard does not name. A document carrying them loses them on the way
/// into this model, which is the price of holding one model rather than two.
const Map<String, String> facturxMetByConstruction = {
  'BR-FXEXT-02': 'The model has no coded line free text beside BT-127.',
  'BR-FXEXT-03': 'The model has none of the parties the extension adds.',
  'BR-FXEXT-06': 'The model has no parent line, so no line has a subtype.',
  'BR-FXEXT-08': 'The model has no subtotal line to sum.',
  'BR-FXEXT-11': 'The model has no parent line to point anywhere.',
  'BR-FXEXT-12': 'The model has no group line to sum.',
};

/// The rules no program can decide.
const Map<String, String> facturxNotMachineCheckable = {
  'BR-FXEXT-04':
      'Whether an item attribute name (BT-160) is one of UNTDED 6313 is a '
      'recommendation, and the artefacts assert nothing for it.',
};

/// The rules that are about the document rather than the invoice.
const Map<String, String> facturxForTheSyntax = {
  'BR-FXEXT-CII-DT-097a':
      'A date and time under format="205" is written YYYYMMDDHHMMSS.',
};

// --- What Factur-X asks that the standard does not --------------------------

Iterable<RuleViolation> _co25(Invoice invoice, RuleDescriptor rule) sync* {
  if (invoice.totals.amountDueForPayment <= Decimal.zero) return;
  if (invoice.dueDate != null) return;
  if (!_blank(invoice.paymentTerms)) return;
  yield _at(
    rule,
    'There is ${invoice.totals.amountDueForPayment} to pay (BT-115), so the '
    'invoice says by when: either the due date (BT-9) or the payment terms '
    '(BT-20).',
  );
}

Iterable<RuleViolation> _fxext01(Invoice invoice, RuleDescriptor rule) sync* {
  for (final (index, note) in invoice.notes.indexed) {
    if (_blank(note.subjectCode) || !_blank(note.text)) continue;
    yield _at(
      rule,
      'The note says what it is about (BT-21) but says nothing (BT-22).',
      'note $index',
    );
  }
}

// --- The totals, within a cent per amount -----------------------------------

Iterable<RuleViolation> _co10(Invoice invoice, RuleDescriptor rule) sync* {
  yield* _within(
    rule,
    actual: invoice.totals.sumOfLineNetAmounts,
    expected: _sum(invoice.lines.map((line) => line.netAmount)),
    count: invoice.lines.length,
    term: 'sum of the line net amounts (BT-106)',
  );
}

Iterable<RuleViolation> _co11(Invoice invoice, RuleDescriptor rule) sync* {
  final allowances = _entries(invoice, AllowanceOrCharge.allowance);
  yield* _within(
    rule,
    actual: invoice.totals.sumOfAllowances ?? Decimal.zero,
    expected: _sum(allowances.map((entry) => entry.amount)),
    count: allowances.length,
    term: 'sum of the document level allowances (BT-107)',
  );
}

Iterable<RuleViolation> _co12(Invoice invoice, RuleDescriptor rule) sync* {
  final charges = _entries(invoice, AllowanceOrCharge.charge);
  yield* _within(
    rule,
    actual: invoice.totals.sumOfCharges ?? Decimal.zero,
    expected: _sum(charges.map((entry) => entry.amount)),
    count: charges.length,
    term: 'sum of the document level charges (BT-108)',
  );
}

Iterable<RuleViolation> _co13(Invoice invoice, RuleDescriptor rule) sync* {
  final allowances = _entries(invoice, AllowanceOrCharge.allowance);
  final charges = _entries(invoice, AllowanceOrCharge.charge);
  yield* _within(
    rule,
    actual: invoice.totals.totalWithoutVat,
    expected:
        _sum(invoice.lines.map((line) => line.netAmount)) -
        _sum(allowances.map((entry) => entry.amount)) +
        _sum(charges.map((entry) => entry.amount)),
    count: invoice.lines.length + allowances.length + charges.length,
    term: 'total without VAT (BT-109)',
  );
}

Iterable<RuleViolation> _co15(Invoice invoice, RuleDescriptor rule) sync* {
  final vat = invoice.totals.totalVat;
  if (vat == null) return;
  yield* _within(
    rule,
    actual: invoice.totals.totalWithVat,
    expected: invoice.totals.totalWithoutVat + vat,
    count: _contributors(invoice),
    term: 'total with VAT (BT-112)',
  );
}

Iterable<RuleViolation> _s09b(Invoice invoice, RuleDescriptor rule) sync* {
  for (final (index, entry) in invoice.vatBreakdown.indexed) {
    if (entry.category != VatCategory.standardRate) continue;
    final rate = entry.rate;
    if (rate == null) continue;
    yield* _within(
      rule,
      actual: entry.taxAmount,
      expected: (entry.taxableAmount * rate / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 20,
      ),
      count: _contributors(invoice, category: VatCategory.standardRate),
      term: 'VAT of the breakdown entry (BT-117)',
      path: 'VAT breakdown $index',
    );
  }
}

/// The taxable amount of each entry of [category], within a cent per amount.
FacturxCheck _breakdown(VatCategory category) => (invoice, rule) sync* {
  for (final (index, entry) in invoice.vatBreakdown.indexed) {
    if (entry.category != category) continue;
    final rate = _byRate.contains(category) ? entry.rate : null;
    final lines = invoice.lines
        .where((line) => line.vatCategory == category)
        .where((line) => rate == null || line.vatRate == rate)
        .toList();
    final entries = invoice.allowancesAndCharges
        .where((item) => item.vatCategory == category)
        .where((item) => rate == null || item.vatRate == rate)
        .toList();
    final allowances = entries.where(
      (e) => e.kind == AllowanceOrCharge.allowance,
    );
    final charges = entries.where((e) => e.kind == AllowanceOrCharge.charge);
    yield* _within(
      rule,
      actual: entry.taxableAmount,
      expected:
          _sum(lines.map((line) => line.netAmount)) -
          _sum(allowances.map((item) => item.amount)) +
          _sum(charges.map((item) => item.amount)),
      count: lines.length + entries.length,
      term: 'taxable amount of the breakdown entry (BT-116)',
      path: 'VAT breakdown $index',
    );
  }
};

// --- Helpers ----------------------------------------------------------------

/// Reports a total that is further out than the tolerance allows.
///
/// EXTENDED gives a cent of room for every amount that went into the total,
/// where the standard asks the figures to meet exactly. An invoice built from
/// prices with more than two decimals lands inside that room and outside the
/// standard.
Iterable<RuleViolation> _within(
  RuleDescriptor rule, {
  required Decimal actual,
  required Decimal expected,
  required int count,
  required String term,
  String? path,
}) sync* {
  final drift = (actual - expected).abs();
  final allowed = _cent * Decimal.fromInt(count);
  if (drift <= allowed) return;
  yield _at(
    rule,
    'The $term is $actual where $expected comes out of the figures, a '
    'difference of $drift where $allowed is allowed.',
    path,
  );
}

/// How many amounts went into the totals, which is what sets the tolerance.
int _contributors(Invoice invoice, {VatCategory? category}) {
  final lines = invoice.lines
      .where((line) => category == null || line.vatCategory == category)
      .length;
  final entries = invoice.allowancesAndCharges
      .where((entry) => category == null || entry.vatCategory == category)
      .length;
  return lines + entries;
}

Iterable<DocumentAllowanceCharge> _entries(
  Invoice invoice,
  AllowanceOrCharge kind,
) => invoice.allowancesAndCharges.where((entry) => entry.kind == kind);

/// The rule of the standard, reported under the identifier Factur-X uses.
FacturxCheck _borrow(String id) => (invoice, rule) {
  final check = _standard[id];
  return check == null ? const <RuleViolation>[] : check(invoice, rule);
};

Decimal _sum(Iterable<Decimal> amounts) =>
    amounts.fold(Decimal.zero, (total, amount) => total + amount);

bool _blank(String? value) => value == null || value.trim().isEmpty;

RuleViolation _at(RuleDescriptor rule, String message, [String? path]) =>
    RuleViolation(rule: rule, message: message, path: path);
