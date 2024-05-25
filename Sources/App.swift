/* Goals

  - [x] make an HTTP server that serves "Hello, world!";
  - [ ] check out the code;
  - [ ] make it talk to Postgres and return `select now()` instead;
  - [ ] run it on Ubuntu.

*/

@main
struct App {
  static func main () {
    let server = SwiftServer()

    try! server.listen(
      hostname: "127.0.0.1",
      portNumber: 3000
    )
  }
}
