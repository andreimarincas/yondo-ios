//
//  MultipartFormBuilder.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import Foundation
import os

nonisolated struct MultipartFormBuilder: Sendable {

    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
        Log.debug("MultipartFormBuilder initialized with boundary: \(boundary)")
    }

    // MARK: - Public API

    mutating func addField(name: String, value: String) {
        Log.debug("MultipartFormBuilder addField: \(name)")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data
    ) {
        Log.debug("MultipartFormBuilder addFile: \(name), filename: \(filename), size: \(data.count) bytes")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func build() -> Data {
        Log.debug("MultipartFormBuilder build called, body size: \(body.count) bytes")
        var finalBody = body
        finalBody.append("--\(boundary)--\r\n")
        return finalBody
    }

    var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

// MARK: - Data helpers

private nonisolated extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
