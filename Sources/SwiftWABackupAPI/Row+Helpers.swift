//
//  Row+Helpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 16/4/25.
//


import Foundation
import GRDB

public extension Row {

    /// Returns the typed column value, or `defaultValue` when the column is `NULL`
    /// or not present in the row.
    func value<T>(for column: String, default defaultValue: T) -> T {
        return self[column] as? T ?? defaultValue
    }

    /// Converts a numeric timestamp (`Int`, `Int64`, or `Double`) into a `Date`
    /// using `timeIntervalSinceReferenceDate`.
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
