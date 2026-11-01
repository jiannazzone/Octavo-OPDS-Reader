import Foundation
@testable import OctavoKit

/// A transport with none of #9's trust rules, for stub servers and the
/// local dev servers. Once #9 merges, tests use
/// `ServerTransport(server:policy:configuration:)` with the stub protocol
/// in `configuration.protocolClasses` instead, and this goes.
struct SessionTransport: HTTPTransport {
    let session: URLSession

    init(_ configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: nil)
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        try await session.download(for: request, delegate: delegate)
    }
}
