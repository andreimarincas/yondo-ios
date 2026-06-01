//
//  SyncService.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.04.2026.
//

import Foundation

@MainActor
protocol SyncService: Sendable {
    func forceRefreshFromCloud() async
    func verifyPremiumWithServer(allowDowngrade: Bool) async throws -> Bool
    func flushBuffers() async
}
