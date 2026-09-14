import 'dart:convert';
import 'dart:typed_data';

import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

const String _xml = '<?xml version="1.0"?><rsm:CrossIndustryInvoice/>';

void main() {
  group('a document that already describes itself', () {
    late Uint8List hybrid;

    setUp(() {
      hybrid = attachFacturxXml(
        _pdfWithMetadata(),
        _xml,
        profile: FacturxProfile.en16931,
      );
    });

    test('has its metadata pointer moved, not doubled', () {
      // A PDF dictionary holds a key once. Writing a second /Metadata beside
      // the first makes it invalid, and every PDF/A file points at its own,
      // so this would break the very documents Factur-X is made of.
      final catalogue = _lastCatalogue(hybrid);
      expect(RegExp(r'/Metadata\s').allMatches(catalogue), hasLength(1));
    });

    test('keeps the conformance it claimed', () {
      expect(pdfaConformance(_pdfWithMetadata()), '3B');
      expect(
        pdfaConformance(hybrid),
        '3B',
        reason: 'writing over the metadata would take the claim with it',
      );
    });

    test('gains the Factur-X properties beside its own', () {
      final text = latin1.decode(hybrid, allowInvalid: true);
      expect(text, contains('<dc:title>Facture</dc:title>'));
      expect(text, contains('<fx:DocumentType>INVOICE</fx:DocumentType>'));
      expect(
        text,
        contains('<fx:ConformanceLevel>EN 16931</fx:ConformanceLevel>'),
      );
      expect(text, contains('Factur-X PDFA Extension Schema'));
    });

    test('still gives back the invoice it carries', () {
      expect(readFacturxXml(hybrid), _xml);
    });
  });

  group('merging the metadata', () {
    test('adds the descriptions before the RDF closes', () {
      final merged = mergeFacturxXmp(_xmp(), FacturxProfile.basic);
      expect(merged, contains('<dc:title>Facture</dc:title>'));
      expect(merged, contains('fx:ConformanceLevel>BASIC<'));
      expect(
        merged.indexOf('fx:DocumentType'),
        lessThan(merged.indexOf('</rdf:RDF>')),
      );
    });

    test('falls back rather than write something unreadable', () {
      // Writing nonsense over readable metadata is the worse of the two
      // failures, so metadata that is not the expected RDF is replaced whole.
      final merged = mergeFacturxXmp('not xmp at all', FacturxProfile.basic);
      expect(merged, contains('<fx:DocumentType>INVOICE</fx:DocumentType>'));
    });
  });
}

/// The catalogue as the update rewrote it, which is the last one written.
String _lastCatalogue(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final at = text.lastIndexOf('1 0 obj');
  return text.substring(at, text.indexOf('endobj', at));
}

/// Metadata of the shape a PDF/A-3B file carries.
String _xmp() {
  final buffer = StringBuffer()
    ..write('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>')
    ..write('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
    ..write('<rdf:RDF xmlns:rdf="$_rdf">')
    ..write('<rdf:Description rdf:about="" xmlns:pdfaid="$_pdfaid" ')
    ..write('pdfaid:part="3" pdfaid:conformance="B"/>')
    ..write('<rdf:Description rdf:about="" xmlns:dc="$_dc">')
    ..write('<dc:title>Facture</dc:title>')
    ..write('</rdf:Description>')
    ..write('</rdf:RDF></x:xmpmeta><?xpacket end="w"?>');
  return buffer.toString();
}

const String _rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const String _pdfaid = 'http://www.aiim.org/pdfa/ns/id/';
const String _dc = 'http://purl.org/dc/elements/1.1/';

/// A one page PDF that points at its own metadata, as PDF/A requires.
Uint8List _pdfWithMetadata() {
  const page = 'BT /F1 24 Tf 72 760 Td (Facture) Tj ET';
  const pageDictionary =
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 595 842] /Contents 4 0 R '
      '/Resources << /Font << /F1 5 0 R >> >> >>';
  final xmp = _xmp();
  final metadata =
      '<< /Type /Metadata /Subtype /XML /Length ${xmp.length} >>\n'
      'stream\n$xmp\nendstream';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    pageDictionary,
    '<< /Length ${page.length} >>\nstream\n$page\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    metadata,
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
