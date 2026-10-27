//
//  Symbolication.swift
//  ThreadTrace
//

import Darwin

/// The image and symbol information for one instruction address.
struct ResolvedImage {
    let image: String
    let symbol: String?
    let offset: UInt
}

/// Resolves instruction addresses with the dynamic linker's symbol tables.
enum Symbolication {
    /// Resolves `address` to its image and closest symbol.
    ///
    /// Return addresses point just past the call instruction, so the lookup
    /// uses the preceding byte to find the calling symbol.
    static func resolve(address: UInt, isReturnAddress: Bool) -> ResolvedImage? {
        let lookupAddress = isReturnAddress && address > 0 ? address - 1 : address
        guard let pointer = UnsafeRawPointer(bitPattern: lookupAddress) else {
            return nil
        }

        var info = Dl_info()
        guard dladdr(pointer, &info) != 0, let imagePath = info.dli_fname else {
            return nil
        }

        let image = String(cString: imagePath).split(separator: "/").last.map(String.init) ?? "<unknown>"

        if let symbolName = info.dli_sname {
            let symbolAddress = UInt(bitPattern: info.dli_saddr)
            return ResolvedImage(
                image: image,
                symbol: String(cString: symbolName),
                offset: address >= symbolAddress ? address - symbolAddress : 0
            )
        }

        let imageBase = UInt(bitPattern: info.dli_fbase)
        return ResolvedImage(
            image: image,
            symbol: nil,
            offset: address >= imageBase ? address - imageBase : 0
        )
    }
}
