import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

/// A one page PDF, written out by hand so the test owns every byte of it.
///
/// Building it here rather than checking a file in keeps the test readable:
/// what the attachment is added to is in front of you, offsets included.
Uint8List minimalPdf() {
  const page = 'BT /F1 24 Tf 72 760 Td (Facture 2026-0042) Tj ET';
  const pageDictionary = '<< /Type /Page /Parent 2 0 R '
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

/// The metadata a PDF/A-3B document carries to say what it is.
String pdfaClaim() => [
      '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>',
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">',
      '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
      '<rdf:Description rdf:about=""',
      ' xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"',
      ' pdfaid:part="3" pdfaid:conformance="B"/>',
      '</rdf:RDF></x:xmpmeta>',
    ].join();

const String _xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<rsm:CrossIndustryInvoice '
    'xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100">'
    '<rsm:ExchangedDocument><ram:ID>2026-0042</ram:ID>'
    '</rsm:ExchangedDocument></rsm:CrossIndustryInvoice>';

void main() {
  group('reading', () {
    test('an ordinary PDF carries no invoice, which is not a failure', () {
      expect(readFacturxXml(minimalPdf()), isNull);
      expect(isFacturxPdf(minimalPdf()), isFalse);
    });

    test('something that is not a PDF is refused', () {
      final bytes = Uint8List.fromList(utf8.encode('not a pdf at all'));
      expect(() => readFacturxXml(bytes), throwsA(isA<FacturxPdfException>()));
      expect(isFacturxPdf(bytes), isFalse);
    });
  });

  group('attaching', () {
    late Uint8List hybrid;

    setUp(() {
      hybrid = attachFacturxXml(
        minimalPdf(),
        _xml,
        profile: FacturxProfile.en16931,
      );
    });

    test('gives back the XML it was given', () {
      expect(readFacturxXml(hybrid), _xml);
      expect(isFacturxPdf(hybrid), isTrue);
    });

    test('keeps every byte of what it was given', () {
      final before = minimalPdf();
      expect(hybrid.length, greaterThan(before.length));
      expect(hybrid.sublist(0, before.length), before);
    });

    test('names the attachment the way the specification does', () {
      final text = latin1.decode(hybrid);
      expect(text, contains('/Type /Filespec'));
      expect(text, contains('(factur-x.xml)'));
      expect(text, contains('/AFRelationship /Data'));
      expect(text, contains('/EmbeddedFiles'));
    });

    test('says in its metadata what it is and at which level', () {
      final text = latin1.decode(hybrid);
      expect(text, contains('<fx:DocumentType>INVOICE</fx:DocumentType>'));
      expect(
        text,
        contains('<fx:ConformanceLevel>EN 16931</fx:ConformanceLevel>'),
      );
      expect(text, contains(facturxNamespace));
      expect(
        text,
        contains('Factur-X PDFA Extension Schema'),
        reason: 'PDF/A refuses a namespace the file does not describe',
      );
    });

    test('closes with a cross reference pointing at the one before', () {
      final text = latin1.decode(hybrid);
      expect(text, contains('/Prev '));
      expect(text.trimRight(), endsWith('%%EOF'));
      final starts = RegExp(r'startxref\s+(\d+)').allMatches(text).toList();
      expect(starts, hasLength(2));
      final last = int.parse(starts.last.group(1)!);
      expect(latin1.decode(hybrid.sublist(last, last + 4)), 'xref');
    });

    test('carries each level under its own conformance level', () {
      for (final profile in FacturxProfile.values) {
        final bytes = attachFacturxXml(minimalPdf(), _xml, profile: profile);
        expect(
          latin1.decode(bytes),
          contains(
            '<fx:ConformanceLevel>${profile.conformanceLevel}'
            '</fx:ConformanceLevel>',
          ),
          reason: profile.name,
        );
      }
    });

    test('refuses to attach twice rather than write a muddle', () {
      expect(
        () => attachFacturxXml(hybrid, _xml, profile: FacturxProfile.basic),
        throwsA(isA<FacturxPdfException>()),
      );
    });

    test('refuses something that is not a PDF', () {
      expect(
        () => attachFacturxXml(
          Uint8List.fromList(utf8.encode('hello')),
          _xml,
          profile: FacturxProfile.basic,
        ),
        throwsA(isA<FacturxPdfException>()),
      );
    });
  });

  group('PDF/A', () {
    test('an ordinary PDF claims no conformance', () {
      expect(pdfaConformance(minimalPdf()), isNull);
      expect(
        pdfaConformance(
          attachFacturxXml(minimalPdf(), _xml, profile: FacturxProfile.en16931),
        ),
        isNull,
        reason: 'attaching does not make a file PDF/A, and never claims to',
      );
    });

    test('a claim held in a compressed stream is read all the same', () {
      // A real Factur-X document compresses its metadata, so reading only the
      // raw bytes answers null for a file that is in fact PDF/A-3.
      final claim = pdfaClaim();
      final compressed = const ZLibEncoder().encode(utf8.encode(claim));
      final bytes = Uint8List.fromList([
        ...minimalPdf(),
        ...latin1.encode(
          '9 0 obj\n<< /Type /Metadata /Subtype /XML /Filter /FlateDecode '
          '/Length ${compressed.length} >>\nstream\n',
        ),
        ...compressed,
        ...latin1.encode('\nendstream\nendobj\n'),
      ]);
      expect(
        latin1.decode(bytes, allowInvalid: true),
        isNot(contains('pdfaid:part')),
      );
      expect(pdfaConformance(bytes), '3B');
    });
    test('a document that claims 3B is read back as 3B', () {
      final claim = pdfaClaim();
      final bytes = Uint8List.fromList([
        ...minimalPdf(),
        ...latin1.encode(claim),
      ]);
      expect(pdfaConformance(bytes), '3B');
    });
  });
}
