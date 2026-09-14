// Reads the Factur-X rule artefacts and writes the profile catalogue.
//
// The artefacts are the five Schematron files of the Factur-X specification,
// taken from the mirror the Mustang project keeps at
// https://github.com/ZUGFeRD/mustangproject (Apache 2.0). Nothing of their
// content is reproduced here: the messages restate the standard's own text.
// What is taken is which rules each profile asserts, which is the fact that
// makes a profile a profile.
//
// Factur-X does not invent a rule family the way Peppol or XRechnung does.
// Each profile republishes a subset of EN 16931's own rules, so the catalogue
// is a set of identifiers per profile rather than a list of new rules. The
// one exception is EXTENDED, which adds BR-FXEXT.
//
// Usage:
//   dart run tool/generate_catalogue.dart --fetch
//   dart run tool/generate_catalogue.dart [--dump <family>]
import 'dart:io';

import 'package:xml/xml.dart';

/// The release the artefacts are read from.
///
/// A tag rather than a branch, so that generating the catalogue twice gives
/// the same catalogue twice. Factur-X is revised once or twice a year, and
/// reading from a moving branch leaves the package saying which rules each
/// level asserts without being able to say against what.
///
/// Raising this is a deliberate act: bump it, regenerate, and read what the
/// diff says before committing it.
const String artefactRelease = 'core-2.26.0';

const String _base =
    'https://raw.githubusercontent.com/ZUGFeRD/mustangproject/'
    '$artefactRelease/validator/src/main/resources/schematron/ZF_250';

/// The five levels, from the thinnest to the widest, and what each is called
/// in the artefacts.
const Map<String, String> _profiles = {
  'minimum': 'MINIMUM',
  'basicWl': 'BASIC-WL',
  'basic': 'BASIC',
  'en16931': 'EN16931',
  'extended': 'EXTENDED',
};

const String _output = 'lib/src/catalogue.g.dart';

/// A rule the artefacts assert, and where it belongs.
class _Rule {
  _Rule(this.id, this.severity, this.terms);

  final String id;
  final String severity;
  final List<String> terms;
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--fetch')) {
    for (final name in _profiles.values) {
      await _fetch('$_base/FACTUR-X_$name.sch', 'artefacts/facturx-$name.sch');
      await _fetch(
        '$_base/FACTUR-X_${name}_codedb.xml',
        'artefacts/facturx-$name-codes.xml',
      );
    }
  }

  final files = {
    for (final entry in _profiles.entries)
      entry.key: File('artefacts/facturx-${entry.value}.sch'),
  };
  for (final file in files.values) {
    if (file.existsSync()) continue;
    stderr.writeln('Missing ${file.path}. Run with --fetch.');
    exitCode = 1;
    return;
  }

  final dump = arguments.indexOf('--dump');
  if (dump != -1 && dump + 1 < arguments.length) {
    _dump(files['extended']!, arguments[dump + 1]);
    return;
  }

  String? version;
  final core = <String, Set<String>>{};
  final syntax = <String, Set<String>>{};
  final extended = <String, _Rule>{};

  for (final entry in files.entries) {
    final source = entry.value.readAsStringSync();
    version ??= _version(source);
    final coreHere = <String>{};
    final syntaxHere = <String>{};
    for (final rule in _read(source)) {
      if (rule.id.startsWith('BR-FXEXT')) {
        extended.putIfAbsent(rule.id, () => rule);
        coreHere.add(rule.id);
      } else if (_isSyntax(rule.id)) {
        syntaxHere.add(rule.id);
      } else {
        coreHere.add(rule.id);
      }
    }
    core[entry.key] = coreHere;
    syntax[entry.key] = syntaxHere;
  }

  final identifiers = {
    for (final entry in _profiles.entries)
      entry.key: _identifiers(
        File('artefacts/facturx-${entry.value}-codes.xml'),
      ),
  };

  final catalogue = extended.values.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  File(
    _output,
  ).writeAsStringSync(_emit(core, syntax, catalogue, identifiers, version));

  // The emitted lists run past the column the formatter wraps at, so what is
  // written and what is committed would differ by a reflow. Formatting here
  // keeps them the same file, which is what lets the build compare them.
  final formatted = Process.runSync('dart', ['format', _output]);
  if (formatted.exitCode != 0) {
    stderr.writeln('dart format failed: ${formatted.stderr}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Factur-X ${version ?? 'of unknown version'}');
  for (final name in _profiles.keys) {
    stdout.writeln(
      '  ${name.padRight(9)} '
      '${core[name]!.length.toString().padLeft(3)} of the model, '
      '${syntax[name]!.length.toString().padLeft(3)} of the document',
    );
  }
  stdout.writeln('  ${catalogue.length} BR-FXEXT rules');
  stdout.writeln('written to $_output');
}

/// Whether the rule is about the XML document rather than the invoice.
///
/// FX-SCH-A counts elements and looks codes up in a database shipped beside
/// the Schematron, CII-SR and CII-DT are the syntax binding of the standard,
/// and the one Peppol rule borrowed here forbids an empty element. None of
/// them can be decided by looking at a semantic model.
bool _isSyntax(String id) =>
    id.startsWith('FX-SCH-A') ||
    id.startsWith('CII-SR') ||
    id.startsWith('CII-DT') ||
    id.startsWith('PEPPOL-');

/// Prints what the artefacts say about one family, to read while writing it.
void _dump(File file, String family) {
  final document = XmlDocument.parse(file.readAsStringSync());
  final seen = <String>{};
  for (final assertion in document.findAllElements('assert')) {
    final id = assertion.getAttribute('id');
    if (id == null || !id.startsWith(family)) continue;
    if (!seen.add(id)) continue;
    stdout.writeln('$id ${_flat(assertion.innerText)}');
    stdout.writeln('    test: ${_flat(assertion.getAttribute('test')!)}');
  }
  stdout.writeln('${seen.length} rules in $family');
}

String _flat(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<void> _fetch(String url, String target) async {
  Directory('artefacts').createSync(recursive: true);
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} for $url');
    }
    await response.pipe(File(target).openWrite());
    stdout.writeln('Fetched $target');
  } finally {
    client.close();
  }
}

/// The release the artefacts announce in their leading comment.
String? _version(String source) =>
    RegExp(r'Version:\s*([0-9.]+)').firstMatch(source)?.group(1);

/// Every rule one artefact file asserts.
Iterable<_Rule> _read(String source) sync* {
  final document = XmlDocument.parse(source);
  final seen = <String>{};
  for (final assertion in document.findAllElements('assert')) {
    final id = assertion.getAttribute('id');
    if (id == null || !seen.add(id)) continue;
    final severity = assertion.getAttribute('flag') == 'warning'
        ? 'warning'
        : 'fatal';
    yield _Rule(id, severity, _terms(assertion.innerText));
  }
}

/// The business terms a rule bears on, read out of the message.
List<String> _terms(String message) {
  final found = <String>[];
  for (final match in RegExp(
    r'\b(?:BT|BG)-\d+(?:-\d+)?\b',
  ).allMatches(message)) {
    final term = match.group(0)!;
    if (!found.contains(term)) found.add(term);
  }
  return found;
}

/// The specification identifiers (BT-24) a profile is claimed under.
///
/// The Schematron only asks that BT-24 be there; which values it may take is
/// held in the code database shipped beside it. Each profile carries two, its
/// Factur-X identifier and the ZUGFeRD one Germany writes for the same thing,
/// so a reader has to accept both.
List<String> _identifiers(File file) {
  final found = <String>{};
  for (final match in RegExp(
    'urn:(?:factur-x.eu|zugferd.de|cen.eu)[^"<]*',
  ).allMatches(file.readAsStringSync())) {
    final value = match.group(0)!;
    if (value.contains('factur-x.eu') ||
        value.contains('zugferd.de') ||
        value == 'urn:cen.eu:en16931:2017') {
      found.add(value);
    }
  }
  final identifiers = found.toList()..sort();
  return identifiers;
}

String _emit(
  Map<String, Set<String>> core,
  Map<String, Set<String>> syntax,
  List<_Rule> extended,
  Map<String, List<String>> identifiers,
  String? version,
) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by tool/generate_catalogue.dart. Do not edit.')
    ..writeln('//')
    ..writeln('// Read from the five Factur-X Schematron files of release')
    ..writeln('// ${version ?? 'unknown'}. What is taken from them is which')
    ..writeln('// rules each profile asserts, and nothing else.')
    ..writeln()
    ..writeln("import 'package:en16931/en16931.dart';")
    ..writeln()
    ..writeln('/// The release the catalogue was read from.')
    ..writeln("const String facturxVersion = '${version ?? 'unknown'}';")
    ..writeln()
    ..writeln('/// What a profile may be claimed as in BT-24.')
    ..writeln('///')
    ..writeln('/// Two identifiers to a profile: the Factur-X one and the')
    ..writeln('/// ZUGFeRD one Germany writes for the same document. The first')
    ..writeln('/// of each pair is the one this package writes.')
    ..writeln('const Map<String, List<String>> facturxProfileIdentifiers = {');
  for (final entry in identifiers.entries) {
    final values = entry.value.map((value) => "\n    '$value',").join();
    buffer.writeln("  '${entry.key}': [$values\n  ],");
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules of the standard each profile asks for.')
    ..writeln('///')
    ..writeln('/// A profile is a subset: MINIMUM carries so little of the')
    ..writeln('/// invoice that most of the standard has nothing to say about')
    ..writeln('/// it, and holding it to all 223 rules would refuse a document')
    ..writeln('/// France accepts. EXTENDED adds BR-FXEXT on top.')
    ..writeln('const Map<String, Set<String>> facturxProfileRules = {');
  for (final entry in core.entries) {
    final ids = entry.value.toList()..sort(_byIdentifier);
    buffer.writeln("  '${entry.key}': {");
    for (final id in ids) {
      buffer.writeln("    '$id',");
    }
    buffer.writeln('  },');
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules each profile puts on the document rather than on')
    ..writeln('/// the invoice.')
    ..writeln('///')
    ..writeln('/// They count elements and look codes up in the XML, so a')
    ..writeln('/// semantic model cannot answer them. They are listed to be')
    ..writeln('/// counted, not to be run.')
    ..writeln('const Map<String, Set<String>> facturxSyntaxRules = {');
  for (final entry in syntax.entries) {
    final ids = entry.value.toList()..sort(_byIdentifier);
    buffer.writeln("  '${entry.key}': {");
    for (final id in ids) {
      buffer.writeln("    '$id',");
    }
    buffer.writeln('  },');
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// The rules the EXTENDED profile adds to EN 16931.')
    ..writeln('const List<RuleDescriptor> facturxExtendedCatalogue = [');
  for (final rule in extended) {
    final terms = rule.terms.map((term) => "'$term'").join(', ');
    buffer
      ..writeln('  RuleDescriptor(')
      ..writeln("    id: '${rule.id}',")
      ..writeln('    family: RuleFamily.profile,')
      ..writeln('    severity: RuleSeverity.${rule.severity},')
      ..writeln('    terms: [$terms],')
      ..writeln('  ),');
  }
  buffer.writeln('];');
  return buffer.toString();
}

/// BR-2 sorts before BR-10, which a plain string sort gets backwards.
int _byIdentifier(String a, String b) {
  final left = _prefix(a).compareTo(_prefix(b));
  if (left != 0) return left;
  final number = _number(a).compareTo(_number(b));
  if (number != 0) return number;
  return a.compareTo(b);
}

String _prefix(String id) =>
    RegExp(r'^(.*?)-?\d+[a-z]*$').firstMatch(id)?.group(1) ?? id;

int _number(String id) {
  final match = RegExp(r'(\d+)[a-z]*$').firstMatch(id);
  return match == null ? 0 : int.parse(match.group(1)!);
}
