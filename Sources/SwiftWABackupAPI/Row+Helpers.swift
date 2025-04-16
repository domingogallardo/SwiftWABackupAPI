//
//  Row+Helpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 16/4/25.
//


import Foundation
import GRDB

public extension Row {

    /// Devuelve el valor tipado de la columna o `defaultValue` si es `NULL`
    /// o la columna no existe.
    func value<T>(for column: String, default defaultValue: T) -> T {
        return self[column] as? T ?? defaultValue
    }

    /// Convierte automáticamente un timestamp (`Int`, `Int64` o `Double`)
    /// al `Date` basado en `timeIntervalSinceReferenceDate`.
    func date(for column: String,
              default defaultDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> Date {
        if let seconds = self[column] as? Double {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        if let seconds = self[column] as? Int64 {
            return Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
        }
        if let seconds = self[column] as? Int {
            return Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
        }
        return defaultDate
    }
}
