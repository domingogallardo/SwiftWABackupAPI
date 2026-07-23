import Foundation

/// Small streaming SHA-256 implementation used to avoid raising the package's deployment target.
struct ConversationSHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var pending: [UInt8] = []
    private var schedule = [UInt32](repeating: 0, count: 64)
    private var byteCount: UInt64 = 0

    mutating func update(data: Data) {
        let bytes = [UInt8](data)
        byteCount &+= UInt64(bytes.count)
        var offset = 0

        if !pending.isEmpty {
            let required = min(64 - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<required])
            offset = required
            if pending.count == 64 {
                process(pending, offset: 0)
                pending.removeAll(keepingCapacity: true)
            }
        }

        while bytes.count - offset >= 64 {
            process(bytes, offset: offset)
            offset += 64
        }
        if offset < bytes.count {
            pending.append(contentsOf: bytes[offset...])
        }
    }

    mutating func finalizeHex() -> String {
        finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashHex(_ data: Data) -> String {
        var hasher = Self()
        hasher.update(data: data)
        return hasher.finalizeHex()
    }

    private mutating func finalize() -> [UInt8] {
        let bitCount = byteCount &* 8
        pending.append(0x80)
        while pending.count % 64 != 56 {
            pending.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            pending.append(UInt8((bitCount >> UInt64(shift)) & 0xff))
        }

        var offset = 0
        while offset < pending.count {
            process(pending, offset: offset)
            offset += 64
        }
        pending.removeAll(keepingCapacity: false)

        return state.flatMap { word in
            [
                UInt8((word >> 24) & 0xff), UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff), UInt8(word & 0xff)
            ]
        }
    }

    private mutating func process(_ block: [UInt8], offset blockOffset: Int) {
        for index in 0..<16 {
            let offset = blockOffset + index * 4
            schedule[index] = UInt32(block[offset]) << 24
                | UInt32(block[offset + 1]) << 16
                | UInt32(block[offset + 2]) << 8
                | UInt32(block[offset + 3])
        }
        for index in 16..<64 {
            let s0 = rotateRight(schedule[index - 15], by: 7)
                ^ rotateRight(schedule[index - 15], by: 18)
                ^ (schedule[index - 15] >> 3)
            let s1 = rotateRight(schedule[index - 2], by: 17)
                ^ rotateRight(schedule[index - 2], by: 19)
                ^ (schedule[index - 2] >> 10)
            schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
        }

        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]
        var f = state[5]
        var g = state[6]
        var h = state[7]

        for index in 0..<64 {
            let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
            let choice = (e & f) ^ ((~e) & g)
            let temporary1 = h &+ sum1 &+ choice &+ Self.constants[index] &+ schedule[index]
            let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temporary2 = sum0 &+ majority

            h = g
            g = f
            f = e
            e = d &+ temporary1
            d = c
            c = b
            b = a
            a = temporary1 &+ temporary2
        }

        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
        state[5] &+= f
        state[6] &+= g
        state[7] &+= h
    }

    private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
