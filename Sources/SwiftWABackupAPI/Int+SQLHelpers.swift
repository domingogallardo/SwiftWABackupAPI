//
//  Int+SQLHelpers.swift
//  SwiftWABackupAPI
//
//  Mini‑helper para crear listas de ? en sentencias IN.
//

import Foundation

public extension Int {
    /// Returns `"?, ?, ?"` with as many placeholders as the integer value.
    /// Returns an empty string when the value is `0`.
    var questionMarks: String {
        guard self > 0 else { return "" }
        return Array(repeating: "?", count: self).joined(separator: ", ")
    }
}
