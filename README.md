# EN 16931 Factur-X

[![Live demo](https://img.shields.io/badge/Live_demo-comapps.web.app-3c9a70)](https://comapps.web.app/en16931/)
[![Pub Version](https://img.shields.io/pub/v/en16931_facturx?color=0175C2)](https://pub.dev/packages/en16931_facturx)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/en16931_facturx/ci.yml?branch=main&label=build)](https://github.com/raphrmx/en16931_facturx/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux,_Web-22375C.svg)

Factur-X 1.09.2: the five levels a French invoice is issued at, the rules each
one asks for, and the hybrid PDF that carries the XML.

One file, read two ways. The buyer opens a PDF; their software reads the
invoice out of it.

## Install

```yaml
dependencies:
  en16931: ^0.1.2
  en16931_facturx: ^0.1.2
```

## Make the document

Build the invoice, check it at its level, hand it a PDF.

```dart
import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/en16931_facturx.dart';

final invoice = Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 14),
  dueDate: DateTime(2026, 10, 14),
  specificationIdentifier: FacturxProfile.en16931.specificationIdentifier,
  buyerReference: 'CMD-778',
  seller: const Seller(
    name: 'COMAPPS SARL',
    vatIdentifier: 'FR12345678901',
    address: Address(city: 'Paris', postalCode: '75001', country: 'FR'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    address: Address(city: 'Lyon', postalCode: '69001', country: 'FR'),
  ),
  lines: [...],
);

if (validateFacturx(invoice).isEmpty) {
  final document = facturxPdf(pdfBytes, invoice);
}
```

## Read one back

```dart
final invoice = readFacturxInvoice(pdfBytes);

if (invoice == null) {
  print('an ordinary PDF, no invoice inside');
} else {
  for (final violation in validateFacturx(invoice)) {
    print(violation); // [BR-CO-25] There is 1440.00 to pay (BT-115), so ...
  }
}
```

A PDF that carries no invoice gives back null. That is an answer, not a
failure: most PDFs are not hybrid.

## The five levels

A level is not a quality ranking, it is how much of the invoice the XML holds.
France accepts MINIMUM for tax reporting: the PDF is the invoice and the XML
says only who, when and how much.

| | Rules of the standard | What it carries |
| --- | --- | --- |
| `minimum` | 18 | Who, when, how much |
| `basicWl` | 130 | The invoice without its lines |
| `basic` | 198 | The lines as well |
| `en16931` | 200 | Everything the standard asks |
| `extended` | 150, and 61 of its own | Beyond the standard |

This is why `validateFacturx` takes a level and does not simply add to
`validate`. A MINIMUM invoice has no lines at all, so holding it to the whole
standard would refuse a document that is perfectly in order.

```dart
validateFacturx(invoice);                              // at the level BT-24 claims
validateFacturx(invoice, profile: FacturxProfile.basic); // at the level you mean to claim
```

EXTENDED is the interesting one: it takes 51 rules of the standard off and
puts its own in their place, most of them the same rule with a cent of room
per amount. An invoice a cent out is refused at the EN 16931 level and passes
at EXTENDED.

## Worth knowing up front

**Attaching does not make a file PDF/A-3.** A Factur-X invoice has to be one,
and a PDF becomes one by having its fonts embedded and its colours profiled,
which cannot be added afterwards. Give `facturxPdf` an ordinary PDF and the
result is an ordinary PDF with a correct attachment: the XML is where a
reader looks for it, and the file is still not PDF/A-3. Start from a PDF/A-3
and what the document claims about itself is carried through.
`pdfaConformance` reads that claim back.

**The PDF is extended, never rewritten.** The bytes you pass are kept whole
and the new objects are appended after them, so nothing the document already
carried is lost. Its own metadata is kept too, and the Factur-X properties
are added beside what it already said: a file that claims PDF/A-3B still
claims it afterwards. A document whose catalogue is held inside an object
stream cannot be extended this way, and that is refused rather than half
written.

**What has been checked against somebody else's validator.** The Mustang
validator, the reference implementation, reads the attachment out of a
document this package writes and finds the invoice inside valid under
EN 16931. It reports the file as not PDF/A-3 when the PDF it was given was
not one, which is the paragraph above and not a surprise. Whether a PDF/A-3
in gives a PDF/A-3 out is not something this package can claim for you: run
your own file through a validator.

**A document claiming ZUGFeRD is read too.** Germany writes the same file
under its own identifiers, and `FacturxProfile.of` answers to both.

Of the rules Factur-X states itself, 36 are checked here, 18 say nothing more
than another already does, 6 cannot be broken by an invoice built with this
model, 1 is a recommendation the artefacts assert nothing for, and 1 is about
the XML. `BR-CO-25` is checked here because Factur-X asserts it and the CEN
artefacts do not carry it at all.

The catalogue is read from the five Schematron files Factur-X publishes, so it
is complete by construction. A test fails when a rule has no answer.

## What it does not do

It does not draw the PDF: that is your application's business, and this takes
the bytes it produced. What an invoice has to contain is
[en16931](https://pub.dev/packages/en16931)'s business, and the XML is written
by [en16931_cii](https://pub.dev/packages/en16931_cii), which comes with this
package.

Delivery is a separate choice, and an easy one here: a Factur-X document is a
PDF, so it goes through a PDP, over Peppol, or as an attachment to an email,
and reads the same either way.

## License

Released under the [MIT licence](https://pub.dev/packages/en16931_facturx/license).

The profile catalogue is generated from the Schematron files Factur-X
publishes. None of their content is redistributed: what is taken from them is
which rules each level asserts and which identifiers claim it.
