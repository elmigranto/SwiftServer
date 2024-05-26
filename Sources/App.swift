/* Goals

Important ones:

  - [x] make an HTTP server that serves "Hello, world!";
  - [x] check out the code;
  - [x] escape SwfitNIO handlers;
  - [x] make it talk to Postgres and return `select now()` instead;
  - [x] trivial route matching;
  - [x] issue real queries against real database
  - [ ] run it on Ubuntu;
  - [ ] save suggestions.

Clean-up ones:

  - [ ] fix Postgres wrapper to be cleanly start/stop-able;
  - [ ] fix Postgres wrapper to not hang indefinetly on connection issues;
  - [ ] fix "async/await/event loop/promise/feature" mess.

*/

import Foundation
import NIOCore
import NIOHTTP1
import PostgresNIO

@main
struct App {
  static let endpoints: [EndpointDescriptor: HandlerGet] = [
    .get("/api/common-data"): Endpoints.commonData,
    .get("/api/places"): Endpoints.places
  ]

  static let server = SwiftServer(handle)
  static let postgres = Postgres(configuration: .init(
    host: "127.0.0.1",
    port: 5432,
    username: "elmigranto",
    password: nil,
    database: "max",
    tls: .disable
  ))

  static func main () async {
    async let listening = try! server.listen(
      hostname: "192.168.1.215",
      portNumber: 3000
    )

    await postgres.connect()
    try! await listening.get()
  }

  static func send404 (_: QueryRunner) -> Encodable {
    return "404"
  }

  static func handle (head: HTTPRequestHead, body: ByteBuffer, promise: EventLoopPromise<ByteBuffer>) {
    let handler = endpoints.first { key, val in
      switch key {
        case .get(let pathname):
          return head.method == .GET && head.uri == pathname

        case .post(let pathname):
          return head.method == .POST && head.uri == pathname
      }
    }?.value ?? send404

    promise.completeWithTask {
      let reply = try await postgres.lease(handler)

      return ByteBuffer(data: JSON.stringify(reply, pretty: true))
    }
  }
}
