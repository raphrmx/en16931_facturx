## 0.1.4

- The package asks for Dart 3.3 instead of 3.11, so a project that has not
  moved yet can take it.

## 0.1.3

- `homepage` points at the package's card on comapps.web.app, which lists
  every package published under COMAPPS.
- The README badge row carries a Live demo badge, the maintainer again, and a
  licence badge in a colour of its own rather than the grey shields puts in
  every label. Nothing about the library changed.

## 0.1.2

- The metadata of a document that already carries some is kept, and the
  Factur-X properties are added beside it. Until now a second `/Metadata` was
  written into the catalogue next to the first, and a PDF dictionary holds a
  key once: the result was malformed. Every PDF/A file points at its own
  metadata, so this broke the very documents Factur-X is made of, and took the
  conformance claim with it.
- What the Mustang validator says about a document this package writes is now
  known rather than assumed: it reads the attachment out and finds the invoice
  inside valid under EN 16931. The README says so, and says what is still not
  claimed.

## 0.1.1

- The README says what a Factur-X document is good for: it is a PDF, so it
  travels through a PDP, over Peppol, or as an attachment to an email.
- The licence badge and the licence section point at the licence page on
  pub.dev. The README carries no link off to a code host any more.
- The example documents Factur-X publishes, one at each level and one hybrid
  PDF, are checked by the test suite. Run `dart run tool/fetch_examples.dart`
  to pull them in.
- The catalogue is generated from a pinned release of the artefacts,
  `core-2.26.0`, rather than from whatever the mirror branch held that day.

## 0.1.0

First release.

- `FacturxProfile` carries the five levels of Factur-X 1.09.2 and the BT-24
  each is claimed under. A document written by Germany under its ZUGFeRD
  identifier is read as the same level, since it is the same document.
- `validateFacturx` checks an invoice at its level. A Factur-X profile is a
  subset of EN 16931 rather than a layer on top of it, so this runs the rules
  the level asserts and no others: MINIMUM asks for 18 of them where the
  EN 16931 level asks for 200. Holding a MINIMUM invoice to the whole standard
  would refuse a document France accepts, because it carries no lines for most
  of the standard to talk about.
- EXTENDED takes 51 rules of the standard off and puts its own in their place.
  Most are the same rule with a cent of room for every amount that went into
  the total, so an invoice a cent out is refused at the EN 16931 level and
  passes at EXTENDED. The rest widen a rule with terms EN 16931 does not have,
  and those run as the rule of the standard, reported under the identifier
  Factur-X gives it.
- `BR-CO-25` is checked here. It belongs to EN 16931, but the artefacts the
  CEN publishes do not carry it: their catalogue steps from BR-CO-24 to
  BR-CO-26. Factur-X asserts it, so leaving it unanswered would leave a rule
  of the profile unchecked.
- `facturxPdf` makes the hybrid document: the invoice is written as CII, the
  XML is attached under the name the specification fixes, and the metadata
  says at which level. `readFacturxInvoice` takes it back out. A PDF carrying
  no invoice gives back null rather than throwing, because most PDFs are not
  hybrid.
- The PDF is extended rather than rewritten: the bytes given are kept whole
  and the new objects appended after them, as an incremental update. A
  document whose catalogue is held inside an object stream cannot be extended
  that way and is refused, since a half written attachment is worse than none.
- Attaching does not make a file PDF/A-3, and nothing here claims it does. A
  PDF becomes one by having its fonts embedded and its colours profiled, which
  cannot be added afterwards. `pdfaConformance` reads back what a file claims,
  inside its compressed streams as well as in the open, since a document that
  compresses its metadata is still making the claim.
- The XMP carries the PDF/A extension schema beside the four Factur-X
  properties. Without it a validator refuses the file for its metadata rather
  than for its invoice.
- The catalogue is read from the five Schematron files Factur-X publishes,
  through the mirror the Mustang project keeps under Apache 2.0. None of their
  content is reproduced: what is taken is which rules each level asserts and
  which identifiers claim it. Every message and every check here is this
  package's own.
- A test fails when a rule of any level has no answer, so what is covered is a
  fact rather than a claim.
