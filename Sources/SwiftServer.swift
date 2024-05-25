import NIOCore
import NIOHTTP1
import NIOPosix

struct SwiftServer {
  private let handler: (HTTPRequestHead, ByteBuffer) -> ByteBuffer

  init (_ handler: @escaping (HTTPRequestHead, ByteBuffer) -> ByteBuffer) {
    self.handler = handler
  }

  func listen (hostname: String, portNumber: UInt16) throws {
    let socketBootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
    // Specify backlog and enable SO_REUSEADDR for the server itself
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

    // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer(childChannelInitializer)

    // Enable SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)

    let channel = try socketBootstrap.bind(host: hostname, port: Int(portNumber)).wait()
    guard let channelLocalAddress = channel.localAddress else {
      fatalError("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
    }

    print("Server started and listening on \(channelLocalAddress)")

    // This will never unblock as we don't close the ServerChannel
    try channel.closeFuture.wait()
  }

  private func childChannelInitializer(_ channel: Channel) -> EventLoopFuture<Void> {
    return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
      channel.pipeline.addHandler(TestHandler(handler))
    }
  }
}
