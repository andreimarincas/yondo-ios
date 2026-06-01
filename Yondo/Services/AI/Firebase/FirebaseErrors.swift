//
//  FirebaseErrors.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.03.2026.
//

import FirebaseFunctions
import Foundation

enum YondoRemoteError: String {
    case authRequired = "AUTH_REQUIRED"
    case userNotFound = "USER_NOT_FOUND"
    case invalidConfig = "INVALID_CONFIG"
    case premiumRequired = "PREMIUM_REQUIRED"
    case insufficientCredits = "INSUFFICIENT_CREDITS"
    case aiGenFailed = "AI_GEN_FAILED"
}

struct RemoteErrorDetails {
    let code: YondoRemoteError
    let message: String
    let destinationName: String?
}

struct FirebaseErrorParser {
    
    static func parse(_ error: Error) -> RemoteErrorDetails? {
        // 1. Cast to NSError to access userInfo
        let nsError = error as NSError
        
        // 2. Firebase maps the 3rd argument of HttpsError to "details"
        guard let details = nsError.userInfo["details"] as? [String: Any],
              let codeString = details["code"] as? String,
              let code = YondoRemoteError(rawValue: codeString) else {
            return nil
        }
        
        return RemoteErrorDetails(
            code: code,
            message: details["message"] as? String ?? "An error occurred",
            destinationName: details["destinationName"] as? String
        )
    }
}
