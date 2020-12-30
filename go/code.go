package onix

import (
	"encoding/xml"
	"fmt"
)

// ProductIDType Product identifier type code, List 5
type ProductIDType string

// UnmarshalXML is not documented yet.
func (c *ProductIDType) UnmarshalXML(d *xml.Decoder, start xml.StartElement) error {
	var v string
	d.DecodeElement(&v, &start)
	switch v {
  // For example, a publisher’s or wholesaler’s product number. Note that <IDTypeName> is required with proprietary identifiers
  case "01":
		*c = "Proprietary"
  // International Standard Book Number, pre-2007, unhyphenated (10 characters) – now DEPRECATED in ONIX for Books, except where providing historical information for compatibility with legacy systems. It should only be used in relation to products published before 2007 – when ISBN-13 superseded it – and should never be used as the ONLY identifier (it should always be accompanied by the correct GTIN-13 / ISBN-13) For example, a publisher’s or wholesaler’s product number. Note that <IDTypeName> is required with proprietary identifiers
  case "02":
		*c = "ISBN-10"
  // GS1 Global Trade Item Number, formerly known as EAN article number (13 digits)
  case "03":
		*c = "GTIN-13"
	case "04":
		*c = "UPC"
	case "05":
		*c = "ISMN-10"
	case "06":
		*c = "DOI"
	case "13":
		*c = "LCCN"
	case "14":
		*c = "GTIN-14"
	case "15":
		*c = "ISBN-13"
	case "17":
		*c = "Legal deposit number"
	case "22":
		*c = "URN"
	case "23":
		*c = "OCLC number"
	case "24":
		*c = "Co-publisher’s ISBN-13"
	case "25":
		*c = "ISMN-13"
	case "26":
		*c = "ISBN-A"
	case "27":
		*c = "JP e-code"
	case "28":
		*c = "OLCC number"
	case "29":
		*c = "JP Magazine ID"
	case "30":
		*c = "UPC12+5"
	case "31":
		*c = "BNF Control number"
	case "35":
		*c = "ARK"
	default:
		return fmt.Errorf("undefined code has been passed, got [%s]", v)
	}
	return nil
}