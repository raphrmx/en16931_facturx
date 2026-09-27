import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

void main() {
  test('the counts in the README are the ones the package holds', () {
    expect(facturxVersion, '1.09.2');
    expect(implementedFacturxRules, hasLength(36));
    expect(facturxSubsumed, hasLength(18));
    expect(facturxMetByConstruction, hasLength(6));
    expect(facturxNotMachineCheckable, hasLength(1));
    expect(facturxForTheSyntax, hasLength(1));
  });

  test('the table of levels in the README is the catalogue', () {
    int standard(FacturxProfile profile) =>
        profile.rules.where((id) => !id.startsWith('BR-FXEXT')).length;
    expect(standard(FacturxProfile.minimum), 18);
    expect(standard(FacturxProfile.basicWl), 130);
    expect(standard(FacturxProfile.basic), 198);
    expect(standard(FacturxProfile.en16931), 200);
    expect(standard(FacturxProfile.extended), 150);
    expect(
      FacturxProfile.extended.rules.where((id) => id.startsWith('BR-FXEXT')),
      hasLength(61),
    );
  });

  test('EXTENDED takes 51 rules of the standard off', () {
    final en = FacturxProfile.en16931.rules;
    final extended = FacturxProfile.extended.rules;
    final dropped =
        en.difference(extended).where((id) => !id.startsWith('BR-FXEXT'));
    expect(dropped, hasLength(51));
  });
}
