/// Factur-X, the French electronic invoice: a PDF and its XML in one file.
///
/// A profile here is a level rather than a layer. Each of the five says how
/// much of the invoice the document carries, and therefore how much of
/// EN 16931 applies to it: MINIMUM asks for eighteen rules of the standard
/// where the EN 16931 level asks for two hundred. Holding the one to the
/// other refuses a document France accepts.
///
/// The model and the rules of the standard are in `en16931`, and the XML is
/// written by `en16931_cii`. What is here is the levels, the rules each one
/// asks for, and the hybrid PDF that carries the XML.
library;

export 'src/catalogue.g.dart';
export 'src/document.dart';
export 'src/pdf.dart';
export 'src/profile.dart';
export 'src/rules.dart'
    show
        FacturxCheck,
        facturxForTheSyntax,
        facturxMetByConstruction,
        facturxNotMachineCheckable,
        facturxRules,
        facturxSubsumed;
export 'src/validator.dart';
export 'src/xmp.dart' show facturxNamespace, facturxXmp, mergeFacturxXmp;
