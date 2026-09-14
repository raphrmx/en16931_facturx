import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

void main() {
  group('the profiles', () {
    test('are read from the artefacts rather than remembered', () {
      expect(facturxVersion, '1.09.2');
      expect(FacturxProfile.values, hasLength(5));
    });

    test('each ask for more of the standard than the one before', () {
      final counts = [
        for (final profile in FacturxProfile.values)
          profile.rules.where((id) => !id.startsWith('BR-FXEXT')).length,
      ];
      expect(counts[0], 18);
      for (var i = 1; i < 4; i++) {
        expect(counts[i], greaterThan(counts[i - 1]), reason: 'at $i');
      }
    });

    test('EXTENDED trades rules of the standard for its own', () {
      final en = FacturxProfile.en16931.rules;
      final extended = FacturxProfile.extended.rules;
      expect(extended, contains('BR-FXEXT-CO-13'));
      expect(extended, isNot(contains('BR-CO-13')));
      expect(en, contains('BR-CO-13'));
      expect(en, isNot(contains('BR-FXEXT-CO-13')));
    });

    test('are claimed under an identifier of their own', () {
      expect(
        FacturxProfile.minimum.specificationIdentifier,
        'urn:factur-x.eu:1p0:minimum',
      );
      expect(
        FacturxProfile.en16931.specificationIdentifier,
        en16931Specification,
      );
      expect(
        FacturxProfile.extended.specificationIdentifier,
        endsWith('#conformant#urn:factur-x.eu:1p0:extended'),
      );
    });

    test('answer to the ZUGFeRD identifier as well', () {
      expect(
        FacturxProfile.of('urn:zugferd.de:2p0:minimum'),
        FacturxProfile.minimum,
      );
      expect(
        FacturxProfile.of(
          'urn:cen.eu:en16931:2017#compliant#urn:zugferd.de:2p0:basic',
        ),
        FacturxProfile.basic,
      );
    });

    test('do not claim a document that is not Factur-X', () {
      expect(
        FacturxProfile.of('urn:cen.eu:en16931:2017#compliant#urn:x'),
        isNull,
      );
      expect(FacturxProfile.of(null), isNull);
    });
  });

  group('the rules', () {
    test('are answered, every one of every profile', () {
      final answered = {
        ...accountedFacturxRules,
        ...implementedRules,
        ...rulesMetByConstruction.keys,
        ...rulesNotMachineCheckable.keys,
      };
      for (final profile in FacturxProfile.values) {
        expect(
          profile.rules.difference(answered),
          isEmpty,
          reason: 'unanswered at ${profile.name}',
        );
      }
    });

    test('are answered once each', () {
      final buckets = [
        facturxRules.keys,
        facturxSubsumed.keys,
        facturxMetByConstruction.keys,
        facturxNotMachineCheckable.keys,
        facturxForTheSyntax.keys,
      ];
      final all = [for (final bucket in buckets) ...bucket];
      expect(all.toSet(), hasLength(all.length));
    });

    test('account for the whole of what EXTENDED adds', () {
      final own = facturxExtendedCatalogue.map((rule) => rule.id).toSet();
      expect(own, hasLength(61));
      expect(own.difference(accountedFacturxRules), isEmpty);
    });

    test('name a rule some catalogue knows', () {
      for (final id in accountedFacturxRules) {
        expect(facturxRuleFor(id).id, id);
      }
    });

    test('state BR-CO-25, which the CEN artefacts leave out', () {
      expect(
        () => ruleFor('BR-CO-25'),
        throwsArgumentError,
        reason: 'the core catalogue steps from BR-CO-24 to BR-CO-26',
      );
      expect(facturxRuleFor('BR-CO-25').id, 'BR-CO-25');
      expect(FacturxProfile.extended.rules, contains('BR-CO-25'));
    });

    test('leave the document rules to the document', () {
      expect(FacturxProfile.minimum.syntaxRules, hasLength(37));
      expect(FacturxProfile.extended.syntaxRules, hasLength(732));
      for (final profile in FacturxProfile.values) {
        expect(profile.rules.intersection(profile.syntaxRules), isEmpty);
      }
    });
  });
}
