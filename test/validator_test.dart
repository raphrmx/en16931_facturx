import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_facturx/en16931_facturx.dart';
import 'package:test/test.dart';

const _seller = Seller(
  name: 'COMAPPS SARL',
  vatIdentifier: 'FR12345678901',
  address: Address(city: 'Paris', postalCode: '75001', country: 'FR'),
);

const _buyer = Buyer(
  name: 'Client SA',
  address: Address(city: 'Lyon', postalCode: '69001', country: 'FR'),
);

Decimal _d(String value) => Decimal.parse(value);

/// A full invoice, claimed at [profile].
Invoice _invoice(FacturxProfile profile) => Invoice.fromLines(
      number: '2026-0042',
      issueDate: DateTime(2026, 9, 14),
      dueDate: DateTime(2026, 10, 14),
      specificationIdentifier: profile.specificationIdentifier,
      buyerReference: 'CMD-778',
      seller: _seller,
      buyer: _buyer,
      lines: [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Conseil'),
          quantity: 8,
          unitPrice: 150.00,
          vatRate: 20,
          unit: UnitCode.hour,
        ),
      ],
    );

void main() {
  group('a profile decides which rules run', () {
    test('a full invoice holds up at the EN 16931 level', () {
      expect(validateFacturx(_invoice(FacturxProfile.en16931)), isEmpty);
    });

    test('and at every level, since each asks for less or for other', () {
      for (final profile in FacturxProfile.values) {
        expect(
          validateFacturx(_invoice(profile)),
          isEmpty,
          reason: 'at ${profile.name}',
        );
      }
    });

    test('the level is read from BT-24 when none is given', () {
      final invoice = _invoice(FacturxProfile.minimum);
      expect(facturxProfileOf(invoice), FacturxProfile.minimum);
      expect(validateFacturx(invoice), isEmpty);
    });

    test('an invoice claiming no profile is not checked at a guess', () {
      final invoice = Invoice.fromLines(
        number: '1',
        issueDate: DateTime(2026, 9, 14),
        specificationIdentifier: null,
        seller: _seller,
        buyer: _buyer,
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Conseil'),
            quantity: 1,
            unitPrice: 10,
            vatRate: 20,
          ),
        ],
      );
      expect(() => validateFacturx(invoice), throwsArgumentError);

      // Naming the level does not excuse the missing identifier: every level
      // asks for BT-24, MINIMUM included.
      expect(
        validateFacturx(invoice, profile: FacturxProfile.minimum)
            .map((violation) => violation.rule.id),
        contains('BR-01'),
      );
    });
  });

  group('MINIMUM carries almost nothing', () {
    /// What France accepts for tax reporting: who, when, how much. The PDF is
    /// the invoice and the XML says the rest.
    final minimum = Invoice(
      number: '2026-0043',
      issueDate: CalendarDate(2026, 9, 14),
      typeCode: InvoiceTypeCode.commercialInvoice,
      currency: 'EUR',
      specificationIdentifier: FacturxProfile.minimum.specificationIdentifier,
      seller: _seller,
      buyer: _buyer,
      lines: const [],
      vatBreakdown: const [],
      totals: InvoiceTotals(
        sumOfLineNetAmounts: _d('1200.00'),
        totalWithoutVat: _d('1200.00'),
        totalWithVat: _d('1440.00'),
        amountDueForPayment: _d('1440.00'),
        totalVat: _d('240.00'),
      ),
    );

    test('an invoice with no lines holds up at MINIMUM', () {
      expect(validateFacturx(minimum), isEmpty);
    });

    test('and is refused the moment it claims to be more', () {
      final breaches = validateFacturx(minimum, profile: FacturxProfile.basic)
          .map((violation) => violation.rule.id);
      expect(breaches, contains('BR-16'));
    });
  });

  group('EXTENDED trades exact totals for a cent of room', () {
    /// The same invoice twice, with a total a cent away from its lines.
    Invoice drifting(FacturxProfile profile) {
      final lines = [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Conseil'),
          quantity: 1,
          unitPrice: 1200.00,
          vatRate: 20,
        ),
      ];
      return Invoice(
        number: '2026-0044',
        issueDate: CalendarDate(2026, 9, 14),
        dueDate: CalendarDate(2026, 10, 14),
        typeCode: InvoiceTypeCode.commercialInvoice,
        currency: 'EUR',
        specificationIdentifier: profile.specificationIdentifier,
        buyerReference: 'CMD-778',
        seller: _seller,
        buyer: _buyer,
        lines: lines,
        vatBreakdown: [
          VatBreakdown(
            category: VatCategory.standardRate,
            taxableAmount: _d('1200.01'),
            taxAmount: _d('240.00'),
            rate: _d('20'),
          ),
        ],
        totals: InvoiceTotals(
          sumOfLineNetAmounts: _d('1200.00'),
          totalWithoutVat: _d('1200.01'),
          totalWithVat: _d('1440.01'),
          amountDueForPayment: _d('1440.01'),
          totalVat: _d('240.00'),
        ),
      );
    }

    test('the EN 16931 level refuses the cent', () {
      final breaches = validateFacturx(drifting(FacturxProfile.en16931))
          .map((violation) => violation.rule.id);
      expect(breaches, contains('BR-CO-13'));
    });

    test('EXTENDED lets it through', () {
      expect(validateFacturx(drifting(FacturxProfile.extended)), isEmpty);
    });

    test('but not a drift wider than the room it gives', () {
      final invoice = Invoice(
        number: '2026-0045',
        issueDate: CalendarDate(2026, 9, 14),
        dueDate: CalendarDate(2026, 10, 14),
        typeCode: InvoiceTypeCode.commercialInvoice,
        currency: 'EUR',
        specificationIdentifier:
            FacturxProfile.extended.specificationIdentifier,
        buyerReference: 'CMD-778',
        seller: _seller,
        buyer: _buyer,
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Conseil'),
            quantity: 1,
            unitPrice: 1200.00,
            vatRate: 20,
          ),
        ],
        vatBreakdown: [
          VatBreakdown(
            category: VatCategory.standardRate,
            taxableAmount: _d('1210.00'),
            taxAmount: _d('242.00'),
            rate: _d('20'),
          ),
        ],
        totals: InvoiceTotals(
          sumOfLineNetAmounts: _d('1200.00'),
          totalWithoutVat: _d('1210.00'),
          totalWithVat: _d('1452.00'),
          amountDueForPayment: _d('1452.00'),
          totalVat: _d('242.00'),
        ),
      );
      final breaches = validateFacturx(invoice)
          .map((violation) => violation.rule.id)
          .toList();
      expect(breaches, contains('BR-FXEXT-CO-13'));
      expect(breaches, contains('BR-FXEXT-S-08ini'));
    });
  });

  group('BR-CO-25, which the CEN artefacts leave out', () {
    test('asks by when an invoice with something to pay is paid', () {
      final invoice = Invoice(
        number: '2026-0046',
        issueDate: CalendarDate(2026, 9, 14),
        typeCode: InvoiceTypeCode.commercialInvoice,
        currency: 'EUR',
        specificationIdentifier:
            FacturxProfile.extended.specificationIdentifier,
        buyerReference: 'CMD-778',
        seller: _seller,
        buyer: _buyer,
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Conseil'),
            quantity: 1,
            unitPrice: 1200.00,
            vatRate: 20,
          ),
        ],
        vatBreakdown: [
          VatBreakdown(
            category: VatCategory.standardRate,
            taxableAmount: _d('1200.00'),
            taxAmount: _d('240.00'),
            rate: _d('20'),
          ),
        ],
        totals: InvoiceTotals(
          sumOfLineNetAmounts: _d('1200.00'),
          totalWithoutVat: _d('1200.00'),
          totalWithVat: _d('1440.00'),
          amountDueForPayment: _d('1440.00'),
          totalVat: _d('240.00'),
        ),
      );
      expect(
        validateFacturx(invoice).map((violation) => violation.rule.id),
        contains('BR-CO-25'),
      );
    });
  });
}
