//
//  FileBackedWrapper.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.12.2025.
//

import Foundation

@propertyWrapper
struct FileBacked<T: Codable> {
    let fileURL: URL
    private let defaultValue: T

    var wrappedValue: T {
        get {
            guard let data = try? Data(contentsOf: fileURL) else { return defaultValue }
            return (try? JSONDecoder().decode(T.self, from: data)) ?? defaultValue
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                try? data.write(to: fileURL)
            }
        }
    }

    init(filename: String, defaultValue: T) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documents.appendingPathComponent(filename)
        self.defaultValue = defaultValue
    }
}
