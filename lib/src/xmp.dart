import 'package:en16931_facturx/src/profile.dart';

/// The namespace the Factur-X metadata lives in.
const String facturxNamespace =
    'urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#';

/// The metadata a Factur-X document carries about itself.
///
/// A reader looks here before it opens anything: the metadata says that the
/// document is hybrid, what the attachment is called and which level it was
/// issued at, so a reader knows whether to bother unpacking it.
///
/// The extension schema below it is what makes the four properties legal in
/// PDF/A. PDF/A allows no namespace it does not know about unless the file
/// describes it, so a document carrying the properties without the
/// description fails validation for the metadata rather than for the invoice.
String facturxXmp(FacturxProfile profile) => '''
<?xpacket begin="\u{feff}" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/"
        xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#"
        xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#">
      <pdfaExtension:schemas>
        <rdf:Bag>
          <rdf:li rdf:parseType="Resource">
            <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
            <pdfaSchema:namespaceURI>$facturxNamespace</pdfaSchema:namespaceURI>
            <pdfaSchema:prefix>fx</pdfaSchema:prefix>
            <pdfaSchema:property>
              <rdf:Seq>
${_property('DocumentFileName', 'name of the embedded XML invoice file')}
${_property('DocumentType', 'INVOICE')}
${_property('Version', 'The actual version of the Factur-X XML schema')}
${_property('ConformanceLevel', 'The conformance level of the embedded XML')}
              </rdf:Seq>
            </pdfaSchema:property>
          </rdf:li>
        </rdf:Bag>
      </pdfaExtension:schemas>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:fx="$facturxNamespace">
      <fx:DocumentType>INVOICE</fx:DocumentType>
      <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
      <fx:Version>1.0</fx:Version>
      <fx:ConformanceLevel>${profile.conformanceLevel}</fx:ConformanceLevel>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>
''';

String _property(String name, String description) => '''
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>$name</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>$description</pdfaProperty:description>
                </rdf:li>''';
