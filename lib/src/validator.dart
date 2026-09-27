import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/src/catalogue.g.dart';
import 'package:en16931_facturx/src/profile.dart';
import 'package:en16931_facturx/src/rules.dart';

/// BR-CO-25, as Factur-X asserts it.
///
/// The rule belongs to EN 16931, but the artefacts the CEN publishes do not
/// carry it: their catalogue steps from BR-CO-24 to BR-CO-26. Factur-X does
/// assert it, so this package states it rather than leave a rule of the
/// profile unanswered.
const RuleDescriptor facturxBrCo25 = RuleDescriptor(
  id: 'BR-CO-25',
  family: RuleFamily.condition,
  severity: RuleSeverity.fatal,
  terms: ['BT-115', 'BT-9', 'BT-20'],
);

/// The rules Factur-X states itself, indexed by identifier.
final Map<String, RuleDescriptor> _own = {
  facturxBrCo25.id: facturxBrCo25,
  for (final rule in facturxExtendedCatalogue) rule.id: rule,
};

/// The rule [id], wherever it is published.
///
/// Most of what a profile asserts belongs to the standard, so the catalogue
/// of `en16931` answers first and the one here answers for the rest.
RuleDescriptor facturxRuleFor(String id) => _own[id] ?? ruleFor(id);

/// The rules this package evaluates itself.
Set<String> get implementedFacturxRules => facturxRules.keys.toSet();

/// Every rule Factur-X states that this package has an answer for.
Set<String> get accountedFacturxRules => {
      ...implementedFacturxRules,
      ...facturxSubsumed.keys,
      ...facturxMetByConstruction.keys,
      ...facturxNotMachineCheckable.keys,
      ...facturxForTheSyntax.keys,
    };

/// What [invoice] breaks at its profile.
///
/// A Factur-X profile is a subset of the standard rather than a layer on top
/// of it, so this does not run `validate` and add to it: it runs the rules
/// the profile asserts and no others. Holding a MINIMUM invoice to the whole
/// standard would refuse a document France accepts, because MINIMUM carries
/// no lines for most of the standard to talk about.
///
/// The profile is read from BT-24 unless [profile] names one, which is how a
/// document is checked against the level it will be issued at before that
/// level is claimed.
///
/// Throws [ArgumentError] when the invoice claims no Factur-X profile and
/// none is given, since there is then nothing to say which rules apply.
List<RuleViolation> validateFacturx(
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

  final violations = <RuleViolation>[];
  for (final id in level.rules) {
    final own = facturxRules[id];
    if (own != null) {
      violations.addAll(own(invoice, facturxRuleFor(id)));
      continue;
    }
    final standard = _standardChecks[id];
    if (standard == null) continue;
    violations.addAll(standard(invoice, ruleFor(id)));
  }
  violations.sort((a, b) => a.rule.id.compareTo(b.rule.id));
  return violations;
}

/// The rules of the standard `en16931` evaluates, indexed by identifier.
final Map<String, RuleCheck> _standardChecks = {
  ...presenceRules,
  ...conditionRules,
  ...decimalRules,
  ...codeListRules,
  ...vatCategoryRules,
};
