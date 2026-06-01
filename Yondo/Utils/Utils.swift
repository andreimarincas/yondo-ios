//
//  Utils.swift
//  Yondo
//
//  Created by Andrei Marincas on 13.01.2026.
//

import Foundation

func boldYondo(_ text: String) -> AttributedString {
    var attributedString = AttributedString(text)
    
    // We search for "Yondo" but handle cases where it might be "Yondos"
    // By searching for the occurrences in the string:
    var searchRange = attributedString.startIndex..<attributedString.endIndex
    
    // Using a loop to find every instance of "Yondo"
    while let range = attributedString[searchRange].range(of: "Yondo", options: .caseInsensitive) {
        
        var finalRange = range
        
        // Check if the character immediately following "Yondo" is an 's' or 'S'
        // to ensure we bold the full word "Yondos"
        if range.upperBound < attributedString.endIndex {
            // Compute the next character's range safely
            let nextIndex = attributedString.index(afterCharacter: range.upperBound)
            let nextCharRange = range.upperBound..<nextIndex
            
            if let nextChar = attributedString[nextCharRange].characters.first {
                if String(nextChar).caseInsensitiveCompare("s") == .orderedSame {
                    finalRange = range.lowerBound..<nextCharRange.upperBound
                }
            }
        }
        
        // Apply the semantic bolding to the full word
        attributedString[finalRange].inlinePresentationIntent = .stronglyEmphasized
        
        // Move the search pointer past the processed word
        searchRange = finalRange.upperBound..<attributedString.endIndex
    }
    
    return attributedString
}

