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

    func parseListBuckets(from data: Data) throws -> ListBucketsResult {
        let delegate = ListBucketsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListBuckets XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListBucketsResult(
            buckets: delegate.buckets,
            owner: delegate.owner,
            continuationToken: delegate.continuationToken
        )
    }
}

private final class ListBucketsParserDelegate: NSObject, XMLParserDelegate {
    var buckets: [Bucket] = []
    var owner: Owner?
    var continuationToken: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Current bucket being parsed
    private var currentBucketName: String?
    private var currentBucketCreationDate: Date?
    private var currentBucketRegion: String?

    // Owner fields
    private var ownerId: String?
    private var ownerDisplayName: String?

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Bucket" {
            currentBucketName = nil
            currentBucketCreationDate = nil
            currentBucketRegion = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Name" where parent == "Bucket":
            currentBucketName = trimmed
        case "CreationDate" where parent == "Bucket":
            currentBucketCreationDate = Self.dateFormatter.date(from: trimmed) ?? Self.dateFormatterNoFraction.date(from: trimmed)
        case "BucketRegion" where parent == "Bucket":
            currentBucketRegion = trimmed
        case "Bucket":
            if let name = currentBucketName {
                buckets.append(Bucket(name: name, creationDate: currentBucketCreationDate, region: currentBucketRegion))
            }
        case "ID" where parent == "Owner":
            ownerId = trimmed
        case "DisplayName" where parent == "Owner":
            ownerDisplayName = trimmed
        case "Owner":
            if let id = ownerId {
                owner = Owner(id: id, displayName: ownerDisplayName)
            }
        case "ContinuationToken":
            continuationToken = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
