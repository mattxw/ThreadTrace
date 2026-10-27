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

        if let symbolName = info.dli_sname, let symbolAddress = info.dli_saddr {
            let symbolStart = UInt(bitPattern: symbolAddress)
            return ResolvedImage(
                image: image,
                symbol: String(cString: symbolName),
                offset: address >= symbolStart ? address - symbolStart : 0
            )
        }

        let imageBase = UInt(bitPattern: info.dli_fbase)
        return ResolvedImage(
            image: image,
            symbol: nil,
            offset: address >= imageBase ? address - imageBase : 0
        )
    }

    /// Whether `instruction` and `returnAddress` resolve to the same symbol.
    ///
    /// A link register that still points into the sampled function, rather
    /// than at its caller, can be recognized this way.
    static func isSameSymbol(_ instruction: UInt, _ returnAddress: UInt) -> Bool {
        guard instruction > 0, returnAddress > 0 else {
            return false
        }
        guard let instructionPointer = UnsafeRawPointer(bitPattern: instruction) else {
            return false
        }
        guard let returnPointer = UnsafeRawPointer(bitPattern: returnAddress - 1) else {
            return false
        }

        var instructionInfo = Dl_info()
        var returnInfo = Dl_info()
        guard dladdr(instructionPointer, &instructionInfo) != 0 else {
            return false
        }
        guard dladdr(returnPointer, &returnInfo) != 0 else {
            return false
        }
        guard let instructionSymbol = instructionInfo.dli_sname else {
            return false
        }
        guard let returnSymbol = returnInfo.dli_sname else {
            return false
        }
        return instructionInfo.dli_fbase == returnInfo.dli_fbase && strcmp(instructionSymbol, returnSymbol) == 0
    }
}
