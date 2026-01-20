import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class XMLResponseParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []
    private var result: [String: String] = [:]

    func parseError(from data: Data) throws -> S3APIError {
        result = [:]
        elementStack = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse XML", responseBody: String(data: data, encoding: .utf8))
        }

        guard let code = result["Code"],
              let message = result["Message"] else {
            throw S3ParsingError(message: "Missing required error fields", responseBody: String(data: data, encoding: .utf8))
        }

        return S3APIError(
            code: S3APIError.Code(rawValue: code),
            message: message,
            resource: result["Resource"],
            requestId: result["RequestId"]
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result[elementName] = trimmed
        }
        elementStack.removeLast()
        currentText = ""
    }
}
