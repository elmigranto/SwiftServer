import NIOCore
import NIOHTTP1

final class TestHandler : ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  // Request's state.
  private var state = State.idle
  private var keepAlive = false
  private var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "")
  private var body = ByteBuffer()

  /// `(request) -> response` function.
  private let handler: (HTTPRequestHead, ByteBuffer, EventLoopPromise<ByteBuffer>) -> Void

  init (_ handler: @escaping (HTTPRequestHead, ByteBuffer, EventLoopPromise<ByteBuffer>) -> Void) {
    self.handler = handler
  }

  func channelRead (context: ChannelHandlerContext, data: NIOAny) {
    switch (unwrapInboundIn(data)) {
      case .head(let head):
        state.requestReceived()

        self.head = head
        context.write(wrapOutboundOut(.head(createResponseHead(request: head, status: .ok))), promise: nil)

      case .body(var buf):
        // TODO: Do not accept gigabytes of data.
        body.writeBuffer(&buf)

      case .end(_):
        self.state.requestComplete()

        // TODO: async / await
        // TODO: try / cath (maybe?)
        let promise = context.eventLoop.makePromise(of: ByteBuffer.self)
        handler(head, body.slice(), promise)

        promise.futureResult.whenComplete { response in
          switch response {
            case .success(let bytes):
              context.write(self.wrapOutboundOut(.body(.byteBuffer(bytes.slice()))), promise: nil)
              self.completeResponse(context)

            case .failure(let error):
              fatalError("Handler failed: \(error)")
          }
        }
    }
  }

  // TODO: Maybe we need none of these and just `writeAndFlush` with `promise: nil`.
  private func completeResponse(_ context: ChannelHandlerContext) {
    self.state.responseComplete()

    let promise: EventLoopPromise<Void>? = self.keepAlive
      ? nil
      : context.eventLoop.makePromise()

    if !self.keepAlive {
      promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
    }

    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
  }
}

fileprivate enum State {
  case idle
  case waitingForRequestBody
  case sendingResponse

  mutating func requestReceived () {
    precondition(self == .idle, "Invalid state for request received: \(self)")
    self = .waitingForRequestBody
  }

  mutating func requestComplete () {
    precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
    self = .sendingResponse
  }

  mutating func responseComplete () {
    precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
    self = .idle
  }
}

fileprivate func createResponseHead (request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
  var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
  let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }

  if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
    // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers

    switch (request.isKeepAlive, request.version.major, request.version.minor) {
      case (true, 1, 0):
        // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
        head.headers.add(name: "Connection", value: "keep-alive")
      case (false, 1, let n) where n >= 1:
        // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
        head.headers.add(name: "Connection", value: "close")
      default:
        // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
        ()
    }
  }
  return head
}
