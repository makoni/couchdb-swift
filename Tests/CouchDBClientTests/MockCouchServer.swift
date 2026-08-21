import Foundation
import NIO
import NIOHTTP1

/// A minimal in-process stand-in for a CouchDB server.
///
/// `POST /_session` is always answered like CouchDB so the client's authorization step
/// succeeds. Every other request is answered by the `respond` closure, which lets tests
/// produce responses a real server never sends (empty bodies, oversized bodies).
final class MockCouchServer {
	struct Response {
		var status: HTTPResponseStatus = .ok
		var body: Data = Data()
	}

	private let group: MultiThreadedEventLoopGroup
	private var channel: Channel?
	private let respond: @Sendable (_ method: String, _ uri: String) -> Response

	init(respond: @escaping @Sendable (_ method: String, _ uri: String) -> Response) {
		self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
		self.respond = respond
	}

	/// Binds the server to an ephemeral port on loopback and returns the port number.
	func start() throws -> Int {
		let respond = self.respond
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
			.childChannelInitializer { channel in
				channel.pipeline.configureHTTPServerPipeline().flatMap {
					channel.pipeline.addHandler(MockCouchServer.Handler(respond: respond))
				}
			}
		let channel = try bootstrap.bind(host: "127.0.0.1", port: 0).wait()
		self.channel = channel
		return channel.localAddress!.port!
	}

	func stop() throws {
		try channel?.close().wait()
		channel = nil
		let finished = DispatchSemaphore(value: 0)
		let group = self.group
		Task {
			try? await group.shutdownGracefully()
			finished.signal()
		}
		finished.wait()
	}

	// Each `Handler` instance belongs to a single channel and is confined to its event loop thread.
	private final class Handler: ChannelInboundHandler, @unchecked Sendable {
		typealias InboundIn = HTTPServerRequestPart
		typealias OutboundOut = HTTPServerResponsePart

		private let respond: @Sendable (_ method: String, _ uri: String) -> Response
		private var head: HTTPRequestHead?

		init(respond: @escaping @Sendable (_ method: String, _ uri: String) -> Response) {
			self.respond = respond
		}

		func channelRead(context: ChannelHandlerContext, data: NIOAny) {
			let part = self.unwrapInboundIn(data)
			switch part {
			case .head(let head):
				self.head = head
			case .body:
				break
			case .end:
				guard let head else { return }
				self.writeResponse(for: head, context: context)
			}
		}

		func errorCaught(context: ChannelHandlerContext, error: Error) {
			context.close(promise: nil)
		}

		private func writeResponse(for head: HTTPRequestHead, context: ChannelHandlerContext) {
			let isSessionRequest = head.method == .POST && head.uri.hasPrefix("/_session")
			let status: HTTPResponseStatus
			let body: Data
			if isSessionRequest {
				status = .ok
				body = Data(#"{"ok":true,"name":"admin","roles":["member"]}"#.utf8)
			} else {
				let response = self.respond(head.method.rawValue, head.uri)
				status = response.status
				body = response.body
			}

			var responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1), status: status)
			responseHead.headers.replaceOrAdd(name: "Content-Type", value: "application/json")
			responseHead.headers.replaceOrAdd(name: "Content-Length", value: String(body.count))
			if isSessionRequest {
				responseHead.headers.replaceOrAdd(
					name: "Set-Cookie",
					value: "auth=mock-session; Path=/; Expires=Thu, 01 Jan 2099 00:00:00 GMT"
				)
			}

			context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
			if !body.isEmpty {
				var buffer = context.channel.allocator.buffer(capacity: body.count)
				buffer.writeBytes(body)
				context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
			}
			context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
		}
	}
}
