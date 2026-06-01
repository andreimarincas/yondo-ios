//
//  _KeyDecoder.swift
//  Yondo
//
//  Created by Andrei Marincas on 31.12.2025.
//

import Foundation

enum _KeyDecoder {

    static func decode(_ encoded: String) -> String {
        let parts = encoded.split(separator: "|")

        let decodedScalars: [UnicodeScalar] = parts.enumerated().flatMap { index, part in
            guard
                let data = Data(base64Encoded: String(part)),
                let string = String(data: data, encoding: .utf8)
            else {
                return [UnicodeScalar]()
            }

            return string.unicodeScalars.map { scalar in
                let shiftedBack = Int(scalar.value) - (index % 3)
                return UnicodeScalar(shiftedBack) ?? scalar
            }
        }

        return String(String.UnicodeScalarView(decodedScalars))
    }
}
