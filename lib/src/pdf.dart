import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:en16931_facturx/src/profile.dart';
import 'package:en16931_facturx/src/xmp.dart';

/// The name the XML is carried under inside the PDF.
///
/// The specification fixes it: a reader looks the attachment up by this name
/// and ignores everything else the document carries. ZUGFeRD 2.x wrote
/// `zugferd-invoice.xml`, which a Factur-X reader still meets in the wild, so
/// reading accepts it and writing never uses it.
const String facturxFilename = 'factur-x.xml';

/// The name ZUGFeRD 2.x used for the same attachment.
const String zugferdFilename = 'zugferd-invoice.xml';

/// What went wrong with a PDF.
class FacturxPdfException implements Exception {
  /// A failure explained by [message].
  const FacturxPdfException(this.message);

  /// What is wrong, in words.
  final String message;

  @override
  String toString() => 'FacturxPdfException: $message';
}

/// The invoice XML carried inside [pdf].
///
/// Returns null when the document carries no attachment this package
/// recognises, which is the answer for an ordinary PDF invoice: it is not an
/// error, it is a PDF that is not hybrid.
///
/// The attachment is looked up by name first, the way a reader does. A
/// document whose file specifications sit inside an object stream hides those
/// names, so a second pass reads every stream and takes the one that turns
/// out to be a Cross Industry Invoice.
///
/// Throws [FacturxPdfException] when [pdf] is not a PDF at all.
String? readFacturxXml(Uint8List pdf) {
  if (!_looksLikePdf(pdf)) {
    throw const FacturxPdfException('Not a PDF: the file has no %PDF header');
  }
  final objects = _objects(pdf);
  final named = _byFilespec(objects);
  if (named != null) return named;
  return _byContent(objects);
}

/// Whether [pdf] carries an invoice this package can read.
bool isFacturxPdf(Uint8List pdf) {
  try {
    return readFacturxXml(pdf) != null;
  } on FacturxPdfException {
    return false;
  }
}

/// [pdf] with [xml] attached to it, claimed at [profile].
///
/// The attachment is added as an incremental update: the bytes of [pdf] are
/// kept whole and the new objects are appended after them, so whatever the
/// document already carried it still carries. A reader that does not know
/// about Factur-X shows the same pages it showed before.
///
/// What this does **not** do is make the result PDF/A-3. A Factur-X invoice
/// has to be PDF/A-3, and a PDF only becomes one by having its fonts
/// embedded, its colours profiled and its metadata declared, none of which
/// can be added after the fact. Give it a PDF/A-3 and the result is one; give
/// it an ordinary PDF and the result is an ordinary PDF with a correct
/// attachment. [pdfaConformance] reads back what the document claims.
///
/// Throws [FacturxPdfException] when the document cannot be extended safely,
/// which happens when its catalogue is held inside an object stream. Failing
/// is the point: a half written attachment is worse than none.
Uint8List attachFacturxXml(
  Uint8List pdf,
  String xml, {
  required FacturxProfile profile,
  String description = 'Invoice metadata conforming to Factur-X',
}) {
  if (!_looksLikePdf(pdf)) {
    throw const FacturxPdfException('Not a PDF: the file has no %PDF header');
  }
  final objects = _objects(pdf);
  final root = _rootReference(pdf);
  if (root == null) {
    throw const FacturxPdfException(
      'No /Root in the trailer, so there is no catalogue to extend',
    );
  }
  final catalogue = objects[root];
  if (catalogue == null) {
    throw FacturxPdfException(
      'The catalogue is object $root, which is not written out on its own. '
      'It is held in an object stream, and this package does not rewrite '
      'those. Convert the file with a PDF tool first.',
    );
  }

  final next = _highestObject(objects) + 1;
  final fileObject = next;
  final specObject = next + 1;
  final metadataObject = next + 2;
  final catalogueObject = root;

  final body = BytesBuilder()..add(pdf);
  if (pdf.isNotEmpty && pdf.last != 0x0a) body.add(const [0x0a]);

  final offsets = <int, int>{};

  void write(int number, List<int> content) {
    offsets[number] = body.length;
    body
      ..add(utf8.encode('$number 0 obj\n'))
      ..add(content)
      ..add(utf8.encode('\nendobj\n'));
  }

  final payload = Uint8List.fromList(utf8.encode(xml));
  final compressed = const ZLibEncoder().encode(payload);
  write(fileObject, [
    ...utf8.encode(
      '<< /Type /EmbeddedFile /Subtype /text#2Fxml /Filter /FlateDecode '
      '/Length ${compressed.length} /Params << /Size ${payload.length} >> '
      '>>\nstream\n',
    ),
    ...compressed,
    ...utf8.encode('\nendstream'),
  ]);

  write(
    specObject,
    utf8.encode(
      '<< /Type /Filespec /F (${_escape(facturxFilename)}) '
      '/UF (${_escape(facturxFilename)}) '
      '/Desc (${_escape(description)}) '
      '/AFRelationship /Data '
      '/EF << /F $fileObject 0 R /UF $fileObject 0 R >> >>',
    ),
  );

  final metadata = utf8.encode(facturxXmp(profile));
  write(metadataObject, [
    ...utf8.encode(
      '<< /Type /Metadata /Subtype /XML /Length ${metadata.length} '
      '>>\nstream\n',
    ),
    ...metadata,
    ...utf8.encode('\nendstream'),
  ]);

  write(
    catalogueObject,
    utf8.encode(
      _extendCatalogue(catalogue.dictionary, specObject, metadataObject),
    ),
  );

  final start = body.length;
  body.add(utf8.encode(_xref(offsets, _highestObject(objects) + 3)));
  body.add(
    utf8.encode(
      'trailer\n<< /Size ${_highestObject(objects) + 3} /Root $root 0 R '
      '/Prev ${_startXref(pdf)} >>\nstartxref\n$start\n%%EOF\n',
    ),
  );
  return body.toBytes();
}

/// What PDF/A conformance [pdf] claims, or null when it claims none.
///
/// A Factur-X document has to be PDF/A-3. This reads what the file says about
/// itself, which is what a validator reads first: a file claiming nothing is
/// not PDF/A, and one claiming 3B says so in its metadata.
///
/// The metadata is looked for in the raw bytes and inside the streams both,
/// because a file that compresses it is still making the claim. Reading only
/// the bytes would answer null for most documents that are in fact PDF/A.
///
/// What comes back is the claim, not a verdict. Whether the file lives up to
/// it takes a PDF/A validator, and this package is not one.
String? pdfaConformance(Uint8List pdf) {
  final claim = _claim(latin1.decode(pdf, allowInvalid: true));
  if (claim != null) return claim;
  for (final object in _objects(pdf).values) {
    if (!object.dictionary.contains('/Metadata') &&
        !object.dictionary.contains('/XML')) {
      continue;
    }
    final content = _content(object);
    if (content == null) continue;
    final found = _claim(content);
    if (found != null) return found;
  }
  return null;
}

/// The PDF/A part and level [text] claims, written as one string.
String? _claim(String text) {
  final part =
      RegExp(r'pdfaid:part\s*=\s*"(\d+)"').firstMatch(text) ??
      RegExp(r'<pdfaid:part>\s*(\d+)\s*<').firstMatch(text);
  if (part == null) return null;
  final level =
      RegExp(r'pdfaid:conformance\s*=\s*"([A-Za-z])"').firstMatch(text) ??
      RegExp(r'<pdfaid:conformance>\s*([A-Za-z])\s*<').firstMatch(text);
  return '${part.group(1)}${level?.group(1)?.toUpperCase() ?? ''}';
}

// --- Reading the file apart -------------------------------------------------

/// One indirect object, as it sits in the file.
class _Object {
  _Object(this.dictionary, this.stream);

  /// The dictionary, from the first `<<` to the matching `>>`.
  final String dictionary;

  /// The bytes between `stream` and `endstream`, when there are any.
  final Uint8List? stream;
}

bool _looksLikePdf(Uint8List pdf) =>
    pdf.length > 5 && latin1.decode(pdf.sublist(0, 5)) == '%PDF-';

/// Every indirect object written out on its own, by number.
///
/// Objects held inside an object stream are not here: reading those means
/// inflating the stream and parsing it, which is only worth doing when the
/// name based lookup fails. [_byContent] covers that case from the other end.
Map<int, _Object> _objects(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final found = <int, _Object>{};
  for (final match in RegExp(r'(\d+)\s+(\d+)\s+obj\b').allMatches(text)) {
    final number = int.parse(match.group(1)!);
    final end = text.indexOf('endobj', match.end);
    if (end == -1) continue;
    final body = text.substring(match.end, end);
    final streamAt = body.indexOf('stream');
    final dictionary = streamAt == -1
        ? body.trim()
        : body.substring(0, streamAt).trim();
    Uint8List? stream;
    if (streamAt != -1) {
      var from = match.end + streamAt + 'stream'.length;
      if (from < pdf.length && pdf[from] == 0x0d) from++;
      if (from < pdf.length && pdf[from] == 0x0a) from++;
      final to = text.indexOf('endstream', from);
      if (to != -1) stream = pdf.sublist(from, _trimEol(pdf, to));
    }
    found[number] = _Object(dictionary, stream);
  }
  return found;
}

int _trimEol(Uint8List pdf, int to) {
  var end = to;
  if (end > 0 && pdf[end - 1] == 0x0a) end--;
  if (end > 0 && pdf[end - 1] == 0x0d) end--;
  return end;
}

int _highestObject(Map<int, _Object> objects) => objects.keys.fold(
  0,
  (highest, number) => number > highest ? number : highest,
);

/// The object number the trailer points at as the catalogue.
int? _rootReference(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final matches = RegExp(r'/Root\s+(\d+)\s+\d+\s+R').allMatches(text).toList();
  if (matches.isEmpty) return null;
  return int.parse(matches.last.group(1)!);
}

int _startXref(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final matches = RegExp(r'startxref\s+(\d+)').allMatches(text).toList();
  return matches.isEmpty ? 0 : int.parse(matches.last.group(1)!);
}

/// The attachment a file specification names, when one of them names ours.
String? _byFilespec(Map<int, _Object> objects) {
  for (final object in objects.values) {
    final dictionary = object.dictionary;
    if (!dictionary.contains('/EF')) continue;
    if (!_namesTheInvoice(dictionary)) continue;
    final embedded = RegExp(
      r'/EF\s*<<[^>]*?/U?F\s+(\d+)\s+\d+\s+R',
    ).firstMatch(dictionary);
    if (embedded == null) continue;
    final target = objects[int.parse(embedded.group(1)!)];
    final content = target == null ? null : _content(target);
    if (content != null) return content;
  }
  return null;
}

bool _namesTheInvoice(String dictionary) =>
    dictionary.contains(facturxFilename) ||
    dictionary.contains(zugferdFilename);

/// The first stream in the file that turns out to be a Cross Industry
/// Invoice.
///
/// This is the way in when the file specifications are hidden inside an
/// object stream. An embedded file is always a stream of its own, so the
/// attachment is reachable even when the dictionary naming it is not.
String? _byContent(Map<int, _Object> objects) {
  for (final object in objects.values) {
    final content = _content(object);
    if (content == null) continue;
    if (!content.contains('CrossIndustryInvoice')) continue;
    return content;
  }
  return null;
}

/// The stream of [object] as text, or null when it is not text at all.
String? _content(_Object object) {
  final stream = object.stream;
  if (stream == null || stream.isEmpty) return null;
  var bytes = stream;
  if (object.dictionary.contains('/FlateDecode')) {
    try {
      bytes = Uint8List.fromList(const ZLibDecoder().decodeBytes(stream));
    } on Object {
      return null;
    }
  }
  try {
    final text = utf8.decode(bytes);
    return text.contains('<') ? text : null;
  } on FormatException {
    return null;
  }
}

// --- Writing the update -----------------------------------------------------

/// The catalogue with the attachment, its name and the metadata added.
///
/// Whatever the catalogue already held is kept: the entries are inserted
/// after the opening `<<` rather than written over. An existing `/AF` or
/// `/Names` would be a document that already carries attachments, which is
/// not something to guess at, so that is refused.
String _extendCatalogue(String dictionary, int spec, int metadata) {
  final opening = dictionary.indexOf('<<');
  if (opening == -1) {
    throw const FacturxPdfException('The catalogue is not a dictionary');
  }
  if (RegExp(r'/AF\b').hasMatch(dictionary) ||
      RegExp(r'/Names\b').hasMatch(dictionary)) {
    throw const FacturxPdfException(
      'The catalogue already carries attachments. Merging them is not '
      'something to guess at, so nothing was written.',
    );
  }
  final added =
      ' /AF [$spec 0 R] /Metadata $metadata 0 R '
      '/Names << /EmbeddedFiles << /Names [(${_escape(facturxFilename)}) '
      '$spec 0 R] >> >>';
  return dictionary.replaceRange(opening + 2, opening + 2, added);
}

/// The cross reference section for the objects this update wrote.
///
/// One subsection per run of consecutive numbers, which is what the format
/// asks for and what keeps a reader from having to guess.
String _xref(Map<int, int> offsets, int size) {
  final numbers = offsets.keys.toList()..sort();
  final buffer = StringBuffer('xref\n');
  var index = 0;
  while (index < numbers.length) {
    var last = index;
    while (last + 1 < numbers.length &&
        numbers[last + 1] == numbers[last] + 1) {
      last++;
    }
    buffer.writeln('${numbers[index]} ${last - index + 1}');
    for (var at = index; at <= last; at++) {
      buffer.writeln(
        '${offsets[numbers[at]]!.toString().padLeft(10, '0')} 00000 n ',
      );
    }
    index = last + 1;
  }
  return buffer.toString();
}

/// A string as a PDF literal, with the three characters that end one escaped.
String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
