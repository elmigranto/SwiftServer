/* Goals

  - [x] make an HTTP server that serves "Hello, world!";
  - [x] check out the code;
  - [x] escape SwfitNIO handlers;
  - [x] make it talk to Postgres and return `select now()` instead;
  - [ ] route matching and so on;
  - [ ] run it on Ubuntu;
  - [ ] fix Postgres wrapper to be cleanly start/stop-able;
  - [ ] fix Postgres wrapper to not hang indefinetly on connection issues;
  - [ ] fix "async/await/event loop/promise/feature" mess.

*/

import NIOCore
import NIOHTTP1
import PostgresNIO

@main
struct App {
  static let server = SwiftServer(handle)
  static let postgres = Postgres(configuration: .init(
    host: "127.0.0.1",
    port: 5432,
    username: "elmigranto",
    password: nil,
    database: "swift-server",
    tls: .disable
  ))

  // TODO: awaits and t
  static func main () async {
    async let listening = try! server.listen(
      hostname: "127.0.0.1",
      portNumber: 3000
    )

    await postgres.connect()
    try! await listening.get()
  }

  static func handle (head: HTTPRequestHead, body: ByteBuffer, promise: EventLoopPromise<ByteBuffer>) {
    promise.completeWithTask {
      let now = await postgres.now()
      let res = "\(String(buffer: body))\n\nPotatoes: \(now)"

      return ByteBuffer(string: res)
    }
  }
}
