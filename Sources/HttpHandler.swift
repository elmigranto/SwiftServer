//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore
import NIOPosix
import NIOHTTP1

fileprivate extension String {
  func chopPrefix(_ prefix: String) -> String? {
    if self.unicodeScalars.starts(with: prefix.unicodeScalars) {
      return String(self[self.index(self.startIndex, offsetBy: prefix.count)...])
    } else {
      return nil
    }
  }
}

fileprivate func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
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

final class HTTPHandler: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias OutboundOut = HTTPServerResponsePart

  private enum State {
    case idle
    case waitingForRequestBody
    case sendingResponse

    mutating func requestReceived() {
      precondition(self == .idle, "Invalid state for request received: \(self)")
      self = .waitingForRequestBody
    }

    mutating func requestComplete() {
      precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
      self = .sendingResponse
    }

    mutating func responseComplete() {
      precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
      self = .idle
    }
  }

  private var buffer: ByteBuffer! = nil
  private var keepAlive = false
  private var state = State.idle

  private var infoSavedRequestHead: HTTPRequestHead?
  private var infoSavedBodyBytes: Int = 0

  private var continuousCount: Int = 0

  private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
  private let defaultResponse = "Hello World\r\n"

  public init () {}

  func handleInfo(context: ChannelHandlerContext, request: HTTPServerRequestPart) {
    switch request {
      case .head(let request):
        self.infoSavedRequestHead = request
        self.infoSavedBodyBytes = 0
        self.keepAlive = request.isKeepAlive
        self.state.requestReceived()
      case .body(buffer: let buf):
        self.infoSavedBodyBytes += buf.readableBytes
      case .end:
        self.state.requestComplete()
        let response = """
            HTTP method: \(self.infoSavedRequestHead!.method)\r
            URL: \(self.infoSavedRequestHead!.uri)\r
            body length: \(self.infoSavedBodyBytes)\r
            headers: \(self.infoSavedRequestHead!.headers)\r
            client: \(context.remoteAddress?.description ?? "zombie")\r
            IO: SwiftNIO Electric Boogaloo™️\r\n
            """
        self.buffer.clear()
        self.buffer.writeString(response)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "\(response.utf8.count)")
        context.write(self.wrapOutboundOut(.head(httpResponseHead(request: self.infoSavedRequestHead!, status: .ok, headers: headers))), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(self.buffer))), promise: nil)
        self.completeResponse(context, trailers: nil, promise: nil)
    }
  }

  func handleEcho(context: ChannelHandlerContext, request: HTTPServerRequestPart) {
    self.handleEcho(context: context, request: request, balloonInMemory: false)
  }

  func handleEcho(context: ChannelHandlerContext, request: HTTPServerRequestPart, balloonInMemory: Bool = false) {
    switch request {
      case .head(let request):
        self.keepAlive = request.isKeepAlive
        self.infoSavedRequestHead = request
        self.state.requestReceived()
        if balloonInMemory {
          self.buffer.clear()
        } else {
          context.writeAndFlush(self.wrapOutboundOut(.head(httpResponseHead(request: request, status: .ok))), promise: nil)
        }
      case .body(buffer: var buf):
        if balloonInMemory {
          self.buffer.writeBuffer(&buf)
        } else {
          context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }
      case .end:
        self.state.requestComplete()
        if balloonInMemory {
          var headers = HTTPHeaders()
          headers.add(name: "Content-Length", value: "\(self.buffer.readableBytes)")
          context.write(self.wrapOutboundOut(.head(httpResponseHead(request: self.infoSavedRequestHead!, status: .ok, headers: headers))), promise: nil)
          context.write(self.wrapOutboundOut(.body(.byteBuffer(self.buffer))), promise: nil)
          self.completeResponse(context, trailers: nil, promise: nil)
        } else {
          self.completeResponse(context, trailers: nil, promise: nil)
        }
    }
  }

  func handleJustWrite(context: ChannelHandlerContext, request: HTTPServerRequestPart, statusCode: HTTPResponseStatus = .ok, string: String, trailer: (String, String)? = nil, delay: TimeAmount = .nanoseconds(0)) {
    switch request {
      case .head(let request):
        self.keepAlive = request.isKeepAlive
        self.state.requestReceived()
        context.writeAndFlush(self.wrapOutboundOut(.head(httpResponseHead(request: request, status: statusCode))), promise: nil)
      case .body(buffer: _):
        ()
      case .end:
        self.state.requestComplete()
        context.eventLoop.scheduleTask(in: delay) { () -> Void in
          var buf = context.channel.allocator.buffer(capacity: string.utf8.count)
          buf.writeString(string)
          context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
          var trailers: HTTPHeaders? = nil
          if let trailer = trailer {
            trailers = HTTPHeaders()
            trailers?.add(name: trailer.0, value: trailer.1)
          }

          self.completeResponse(context, trailers: trailers, promise: nil)
        }
    }
  }

  func handleContinuousWrites(context: ChannelHandlerContext, request: HTTPServerRequestPart) {
    switch request {
      case .head(let request):
        self.keepAlive = request.isKeepAlive
        self.continuousCount = 0
        self.state.requestReceived()
        func doNext() {
          self.buffer.clear()
          self.continuousCount += 1
          self.buffer.writeString("line \(self.continuousCount)\n")
          context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(self.buffer)))).map {
            context.eventLoop.scheduleTask(in: .milliseconds(400), doNext)
          }.whenFailure { (_: Error) in
            self.completeResponse(context, trailers: nil, promise: nil)
          }
        }
        context.writeAndFlush(self.wrapOutboundOut(.head(httpResponseHead(request: request, status: .ok))), promise: nil)
        doNext()
      case .end:
        self.state.requestComplete()
      default:
        break
    }
  }

  func handleMultipleWrites(context: ChannelHandlerContext, request: HTTPServerRequestPart, strings: [String], delay: TimeAmount) {
    switch request {
      case .head(let request):
        self.keepAlive = request.isKeepAlive
        self.continuousCount = 0
        self.state.requestReceived()
        func doNext() {
          self.buffer.clear()
          self.buffer.writeString(strings[self.continuousCount])
          self.continuousCount += 1
          context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(self.buffer)))).whenSuccess {
            if self.continuousCount < strings.count {
              context.eventLoop.scheduleTask(in: delay, doNext)
            } else {
              self.completeResponse(context, trailers: nil, promise: nil)
            }
          }
        }
        context.writeAndFlush(self.wrapOutboundOut(.head(httpResponseHead(request: request, status: .ok))), promise: nil)
        doNext()
      case .end:
        self.state.requestComplete()
      default:
        break
    }
  }

  func dynamicHandler(request reqHead: HTTPRequestHead) -> ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)? {
    if let howLong = reqHead.uri.chopPrefix("/dynamic/write-delay/") {
      return { context, req in
        self.handleJustWrite(context: context,
                             request: req, string: self.defaultResponse,
                             delay: Int64(howLong).map { .milliseconds($0) } ?? .seconds(0))
      }
    }

    switch reqHead.uri {
      case "/dynamic/echo":
        return self.handleEcho
      case "/dynamic/echo_balloon":
        return { self.handleEcho(context: $0, request: $1, balloonInMemory: true) }
      case "/dynamic/pid":
        return { context, req in self.handleJustWrite(context: context, request: req, string: "\(getpid())") }
      case "/dynamic/write-delay":
        return { context, req in self.handleJustWrite(context: context, request: req, string: self.defaultResponse, delay: .milliseconds(100)) }
      case "/dynamic/info":
        return self.handleInfo
      case "/dynamic/trailers":
        return { context, req in self.handleJustWrite(context: context, request: req, string: "\(getpid())\r\n", trailer: ("Trailer-Key", "Trailer-Value")) }
      case "/dynamic/continuous":
        return self.handleContinuousWrites
      case "/dynamic/count-to-ten":
        return { self.handleMultipleWrites(context: $0, request: $1, strings: (1...10).map { "\($0)" }, delay: .milliseconds(100)) }
      case "/dynamic/client-ip":
        return { context, req in self.handleJustWrite(context: context, request: req, string: "\(context.remoteAddress.debugDescription)") }
      default:
        return { context, req in self.handleJustWrite(context: context, request: req, statusCode: .notFound, string: "not found") }
    }
  }

  private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
    self.state.responseComplete()

    let promise = self.keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
    if !self.keepAlive {
      promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
    }
    self.handler = nil

    context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let reqPart = self.unwrapInboundIn(data)
    if let handler = self.handler {
      handler(context, reqPart)
      return
    }

    switch reqPart {
      case .head(let request): // Distinguishes /dynamic* from replying with default response.
        if request.uri.unicodeScalars.starts(with: "/dynamic".unicodeScalars) {
          self.handler = self.dynamicHandler(request: request)
          self.handler!(context, reqPart)
          return
        }

        print("Non-dynamic")

        self.keepAlive = request.isKeepAlive
        self.state.requestReceived()

        var responseHead = httpResponseHead(request: request, status: HTTPResponseStatus.ok)
        self.buffer.clear()
        self.buffer.writeString(self.defaultResponse)
        responseHead.headers.add(name: "content-length", value: "\(self.buffer!.readableBytes)")
        let response = HTTPServerResponsePart.head(responseHead)
        context.write(self.wrapOutboundOut(response), promise: nil)
      case .body:
        break
      case .end:
        self.state.requestComplete()
        let content = HTTPServerResponsePart.body(.byteBuffer(buffer!.slice()))
        context.write(self.wrapOutboundOut(content), promise: nil)
        self.completeResponse(context, trailers: nil, promise: nil)
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    context.flush()
  }

  func handlerAdded(context: ChannelHandlerContext) {
    self.buffer = context.channel.allocator.buffer(capacity: 0)
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch event {
      case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
        // The remote peer half-closed the channel. At this time, any
        // outstanding response will now get the channel closed, and
        // if we are idle or waiting for a request body to finish we
        // will close the channel immediately.
        switch self.state {
          case .idle, .waitingForRequestBody:
            context.close(promise: nil)
          case .sendingResponse:
            self.keepAlive = false
        }
      default:
        context.fireUserInboundEventTriggered(event)
    }
  }
}
