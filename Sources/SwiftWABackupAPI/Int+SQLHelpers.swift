//
//  Int+SQLHelpers.swift
//  SwiftWABackupAPI
//
//  Mini‑helper para crear listas de ? en sentencias IN.
//

import Foundation

public extension Int {
    /// Devuelve "?, ?, ?" con tantas interrogaciones como indique el valor.
    /// Si `self` es 0 devuelve la cadena vacía (no suele usarse).
    var questionMarks: String {
        guard self > 0 else { return "" }
        return Array(repeating: "?", count: self).joined(separator: ", ")
    }
}
