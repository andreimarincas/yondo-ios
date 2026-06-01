//
//  SyncShielding.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
protocol SyncShielding: Sendable {
    var isTransactionActive: Bool { get }
    func startTransaction() -> UUID
    func stopTransaction(id: UUID?)
    
    func forceBypass()
    func clearBypass()
    func resetAll()
}
