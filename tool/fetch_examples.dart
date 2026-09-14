// Downloads one example document per Factur-X level.
//
// They come from https://github.com/akretion/factur-x, which keeps one
// document at each of the five levels. They are read by the test suite and
// never redistributed, so they land in a directory git ignores.
//
// Usage:
//   dart run tool/fetch_examples.dart
import 'dart:io';
import 'dart:typed_data';

const String _raw =
    'https://raw.githubusercontent.com/akretion/factur-x/master/tests/fixtures';

const Map<String, String> _sources = {
  'minimum.xml': '$_raw/xml/factur-x-minimum.xml',
  'basicwl.xml': '$_raw/xml/factur-x-basicwl.xml',
  'basic.xml': '$_raw/xml/factur-x-basic.xml',
  'en16931.xml': '$_raw/xml/factur-x-en16931.xml',
  'extended.xml': '$_raw/xml/factur-x-extended.xml',
  'hybrid.pdf': '$_raw/pdf/invoice_EN16931.pdf',
};

const String _directory = 'examples_from_facturx';

Future<void> main() async {
  final client = HttpClient();
  try {
    Directory(_directory).createSync(recursive: true);
    for (final entry in _sources.entries) {
      final bytes = await _bytes(client, entry.value);
      File('$_directory/${entry.key}').writeAsBytesSync(bytes);
      stdout.writeln('${entry.key}: ${bytes.length} bytes');
    }
  } finally {
    client.close();
  }
}

Future<List<int>> _bytes(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', 'en16931_facturx');
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token != null && token.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode} for $url');
  }
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
