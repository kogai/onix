package onix

import (
	"encoding/xml"
	"fmt"
)

type Onix struct {
	XMLName  xml.Name  `xml:"ONIXmessage"`
	Header   Header    `xml:"header"`
	Products []Product `xml:"product"`
}
