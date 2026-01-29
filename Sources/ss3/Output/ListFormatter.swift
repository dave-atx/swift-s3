import Foundation
import SwiftS3

struct ListFormatter: Sendable {
    let longFormat: Bool
    let sortByTime: Bool

    private let humanFormatter = HumanFormatter()

    func formatObjects(_ objects: [S3Object], prefixes: [String]) -> String {
        var lines: [String] = []

        // Sort objects
        let sortedObjects: [S3Object]
        if sortByTime {
            sortedObjects = objects.sorted { obj1, obj2 in
                let date1 = obj1.lastModified ?? Date.distantPast
                let date2 = obj2.lastModified ?? Date.distantPast
                return date1 > date2  // Most recent first
            }
        } else {
            sortedObjects = objects.sorted { $0.key < $1.key }
        }

        // Format objects (files first when sorting by time)
        for object in sortedObjects {
            if longFormat {
                let size = object.size.map { humanFormatter.formatCompactSize($0) } ?? "    -"
                let date = object.lastModified.map { humanFormatter.formatLsDate($0) } ?? "            "
                lines.append("\(size)  \(date)  \(object.key)")
            } else {
                lines.append(object.key)
            }
        }

        // Sort and add prefixes (directories) at the end
        let sortedPrefixes = prefixes.sorted()
        for prefix in sortedPrefixes {
            lines.append(prefix)
        }

        return lines.joined(separator: "\n")
    }

    func formatBuckets(_ buckets: [Bucket]) -> String {
        var lines: [String] = []

        let sortedBuckets: [Bucket]
        if sortByTime {
            sortedBuckets = buckets.sorted { b1, b2 in
                let date1 = b1.creationDate ?? Date.distantPast
                let date2 = b2.creationDate ?? Date.distantPast
                return date1 > date2  // Most recent first
            }
        } else {
            sortedBuckets = buckets.sorted { $0.name < $1.name }
        }

        for bucket in sortedBuckets {
            if longFormat {
                let date = bucket.creationDate.map { humanFormatter.formatLsDate($0) } ?? "            "
                lines.append("\(date)  \(bucket.name)")
            } else {
                lines.append(bucket.name)
            }
        }

        return lines.joined(separator: "\n")
    }

    func formatError(_ error: any Error, verbose: Bool) -> String {
        humanFormatter.formatError(error, verbose: verbose)
    }
}
