import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestBuilder: Sendable {
    let configuration: S3Configuration

    func buildRequest(
        method: String,
        bucket: String?,
        key: String?,
        queryItems: [URLQueryItem]?,
        headers: [String: String]?,
        body: Data?
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = configuration.endpoint.scheme

        if configuration.usePathStyleAddressing {
            // Path-style: https://endpoint/bucket/key
            components.host = configuration.endpoint.host
            components.port = configuration.endpoint.port
            var path = ""
            if let bucket = bucket {
                path += "/\(bucket)"
            }
            if let key = key {
                path += "/\(key)"
            }
            components.path = path.isEmpty ? "/" : path
        } else {
            // Virtual-hosted style: https://bucket.endpoint/key
            let endpointHost = configuration.endpoint.host ?? ""
            if let bucket = bucket {
                components.host = "\(bucket).\(endpointHost)"
            } else {
                components.host = endpointHost
            }
            components.port = configuration.endpoint.port
            if let key = key {
                components.path = "/\(key)"
            } else {
                components.path = "/"
            }
        }

        components.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components.url else {
            fatalError("Failed to construct URL from components: \(components)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        // Set Host header
        request.setValue(components.host, forHTTPHeaderField: "Host")

        // Set custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }
}
