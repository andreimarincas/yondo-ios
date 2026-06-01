//
//  IAPErrors.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import Foundation

enum PurchaseError: Error {
    case productNotFound
    case verificationFailed(Error?)
    case cancelled
    case pending            // Parent needs to approve
    case invalidState
    case unknown
}

enum StoreError: LocalizedError, Equatable {
    case emptyRegion
    case networkIssue(Error)
    case insufficientFunds
    case busy
    case persistenceFailure(Error)
    case missingUser
    
    var errorDescription: String? {
        switch self {
        case .insufficientFunds:
            return "You don't have enough credits for this action."
        case .busy:
            return "The store is currently processing another request. Please try again in a moment."
        case .emptyRegion:
            return "We couldn't find any items for sale in your region."
        case .networkIssue(let error):
            return error.localizedDescription
        case .persistenceFailure(let error):
            return "We couldn't secure your credit balance: \(error.localizedDescription)"
        case .missingUser:
            return "Unable to verify your account. Please check your internet connection and try again."
        }
    }
    
    static func == (lhs: StoreError, rhs: StoreError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyRegion, .emptyRegion),
             (.insufficientFunds, .insufficientFunds),
             (.busy, .busy),
             (.missingUser, .missingUser):
            return true
            
        case let (.networkIssue(le), .networkIssue(re)):
            // Cast to NSError to compare Domain and Code
            let l = le as NSError
            let r = re as NSError
            return l.domain == r.domain && l.code == r.code
            
        case let (.persistenceFailure(le), .persistenceFailure(re)):
            // Cast to NSError to compare Domain and Code
            let l = le as NSError
            let r = re as NSError
            return l.domain == r.domain && l.code == r.code
            
        default:
            return false
        }
    }
}
