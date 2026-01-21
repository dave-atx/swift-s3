import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses an ISO8601 date string, trying with and without fractional seconds
private func parseISO8601Date(_ string: String) -> Date? {
    let formatterWithFraction = ISO8601DateFormatter()
    formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatterWithFraction.date(from: string) {
        return date
    }
    let formatterNoFraction = ISO8601DateFormatter()
    formatterNoFraction.formatOptions = [.withInternetDateTime]
    return formatterNoFraction.date(from: string)
}

final class XMLResponseParser: NSObject, XMLParserDelegate {
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

    func parseListObjects(from data: Data) throws -> ListObjectsResult {
        let delegate = ListObjectsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListObjects XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListObjectsResult(
            name: delegate.name ?? "",
            prefix: delegate.prefix,
            objects: delegate.objects,
            commonPrefixes: delegate.commonPrefixes,
            isTruncated: delegate.isTruncated,
            continuationToken: delegate.continuationToken
        )
    }

    func parseInitiateMultipartUpload(from data: Data) throws -> MultipartUpload {
        result = [:]
        elementStack = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse InitiateMultipartUpload XML", responseBody: String(data: data, encoding: .utf8))
        }

        guard let uploadId = result["UploadId"],
              let key = result["Key"] else {
            throw S3ParsingError(message: "Missing required fields", responseBody: String(data: data, encoding: .utf8))
        }

        return MultipartUpload(uploadId: uploadId, key: key, initiated: nil)
    }

    func parseListMultipartUploads(from data: Data) throws -> ListMultipartUploadsResult {
        let delegate = ListMultipartUploadsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListMultipartUploads XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListMultipartUploadsResult(
            uploads: delegate.uploads,
            isTruncated: delegate.isTruncated,
            nextKeyMarker: delegate.nextKeyMarker,
            nextUploadIdMarker: delegate.nextUploadIdMarker
        )
    }

    func parseListParts(from data: Data) throws -> ListPartsResult {
        let delegate = ListPartsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw S3ParsingError(message: "Failed to parse ListParts XML", responseBody: String(data: data, encoding: .utf8))
        }

        return ListPartsResult(
            parts: delegate.parts,
            isTruncated: delegate.isTruncated,
            nextPartNumberMarker: delegate.nextPartNumberMarker
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
            currentBucketCreationDate = parseISO8601Date(trimmed)
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

private final class ListObjectsParserDelegate: NSObject, XMLParserDelegate {
    var objects: [S3Object] = []
    var commonPrefixes: [String] = []
    var name: String?
    var prefix: String?
    var isTruncated: Bool = false
    var continuationToken: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Current object being parsed
    private var currentKey: String?
    private var currentLastModified: Date?
    private var currentEtag: String?
    private var currentSize: Int64?
    private var currentStorageClass: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Contents" {
            currentKey = nil
            currentLastModified = nil
            currentEtag = nil
            currentSize = nil
            currentStorageClass = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Name" where parent == "ListBucketResult":
            name = trimmed
        case "Prefix" where parent == "ListBucketResult":
            prefix = trimmed.isEmpty ? nil : trimmed
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextContinuationToken":
            continuationToken = trimmed.isEmpty ? nil : trimmed
        case "Key" where parent == "Contents":
            currentKey = trimmed
        case "LastModified" where parent == "Contents":
            currentLastModified = parseISO8601Date(trimmed)
        case "ETag" where parent == "Contents":
            currentEtag = trimmed
        case "Size" where parent == "Contents":
            currentSize = Int64(trimmed)
        case "StorageClass" where parent == "Contents":
            currentStorageClass = trimmed
        case "Contents":
            if let key = currentKey {
                objects.append(S3Object(
                    key: key,
                    lastModified: currentLastModified,
                    etag: currentEtag,
                    size: currentSize,
                    storageClass: currentStorageClass,
                    owner: nil
                ))
            }
        case "Prefix" where parent == "CommonPrefixes":
            commonPrefixes.append(trimmed)
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}

private final class ListMultipartUploadsParserDelegate: NSObject, XMLParserDelegate {
    var uploads: [MultipartUpload] = []
    var isTruncated = false
    var nextKeyMarker: String?
    var nextUploadIdMarker: String?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    private var currentKey: String?
    private var currentUploadId: String?
    private var currentInitiated: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Upload" {
            currentKey = nil
            currentUploadId = nil
            currentInitiated = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "Key" where parent == "Upload":
            currentKey = trimmed
        case "UploadId" where parent == "Upload":
            currentUploadId = trimmed
        case "Initiated" where parent == "Upload":
            currentInitiated = parseISO8601Date(trimmed)
        case "Upload":
            if let key = currentKey, let uploadId = currentUploadId {
                uploads.append(MultipartUpload(uploadId: uploadId, key: key, initiated: currentInitiated))
            }
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextKeyMarker":
            nextKeyMarker = trimmed.isEmpty ? nil : trimmed
        case "NextUploadIdMarker":
            nextUploadIdMarker = trimmed.isEmpty ? nil : trimmed
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}

private final class ListPartsParserDelegate: NSObject, XMLParserDelegate {
    var parts: [Part] = []
    var isTruncated = false
    var nextPartNumberMarker: Int?

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    private var currentPartNumber: Int?
    private var currentEtag: String?
    private var currentSize: Int64?
    private var currentLastModified: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "Part" {
            currentPartNumber = nil
            currentEtag = nil
            currentSize = nil
            currentLastModified = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : ""

        switch elementName {
        case "PartNumber" where parent == "Part":
            currentPartNumber = Int(trimmed)
        case "ETag" where parent == "Part":
            currentEtag = trimmed
        case "Size" where parent == "Part":
            currentSize = Int64(trimmed)
        case "LastModified" where parent == "Part":
            currentLastModified = parseISO8601Date(trimmed)
        case "Part":
            if let partNumber = currentPartNumber, let etag = currentEtag {
                parts.append(Part(partNumber: partNumber, etag: etag, size: currentSize, lastModified: currentLastModified))
            }
        case "IsTruncated":
            isTruncated = trimmed.lowercased() == "true"
        case "NextPartNumberMarker":
            nextPartNumberMarker = Int(trimmed)
        default:
            break
        }

        elementStack.removeLast()
        currentText = ""
    }
}
