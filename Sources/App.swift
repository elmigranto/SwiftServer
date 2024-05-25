/* Goals

  - [x] make an HTTP server that serves "Hello, world!";
  - [x] check out the code;
  - [x] escape SwfitNIO handlers;
  - [ ] make it talk to Postgres and return `select now()` instead;
  - [ ] route matching and so on;
  - [ ] run it on Ubuntu.

*/

import NIOCore
import NIOHTTP1

@main
struct App {
  static func main () {
    let server = SwiftServer(handle)

    try! server.listen(
      hostname: "127.0.0.1",
      portNumber: 3000
    )
  }

  static func handle (head: HTTPRequestHead, body: ByteBuffer) -> ByteBuffer {
    return ByteBuffer(string: "\(String(buffer: body))\n\nPotatoes!")
  }
}
