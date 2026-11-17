// Linux stand-in for Apple's Compression framework (raw DEFLATE only).
import CZlib

public struct compression_algorithm: Equatable { let raw: Int }
public let COMPRESSION_ZLIB = compression_algorithm(raw: 0x205)

public func compression_decode_buffer(_ dst: UnsafeMutablePointer<UInt8>, _ dstSize: Int,
                                      _ src: UnsafePointer<UInt8>, _ srcSize: Int,
                                      _ scratch: UnsafeMutableRawPointer?, _ alg: compression_algorithm) -> Int {
    var s = z_stream()
    guard inflateInit2_(&s, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return 0 }
    s.next_in = UnsafeMutablePointer(mutating: src)
    s.avail_in = UInt32(srcSize)
    s.next_out = dst
    s.avail_out = UInt32(dstSize)
    _ = inflate(&s, Z_FINISH)
    let out = Int(s.total_out)
    inflateEnd(&s)
    return out
}
