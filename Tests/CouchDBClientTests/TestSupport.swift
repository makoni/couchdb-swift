import Foundation
import AsyncHTTPClient
import NIO
@testable import CouchDBClient

func makeByteBuffer(from data: Data) -> ByteBuffer {
	var buffer = ByteBufferAllocator().buffer(capacity: data.count)
	buffer.writeBytes(data)
	return buffer
}

func makeRequestBody(from data: Data) -> HTTPClientRequest.Body {
	.bytes(makeByteBuffer(from: data))
}

func readAllData(from bytes: ByteBuffer) throws -> Data {
	guard bytes.readableBytes > 0 else {
		throw CouchDBClientError.noData
	}

	return Data(bytes.readableBytesView)
}
