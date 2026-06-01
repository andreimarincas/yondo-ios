//
//  SecureCreditStore+Extension.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.04.2026.
//

extension SecureCreditStore {
    var isRunningOnFreeCredits: Bool {
        credits > 0 && !hasPurchasedCredits
    }
}
