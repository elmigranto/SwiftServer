
enum EndpointDescriptor: Hashable {
  case get(_ pathname: String)
  case post(_ pathname: String)
}

typealias HandlerGet = (QueryRunner) async throws -> Encodable
// typealias HandlerPost = (query, body) async -> encodable

