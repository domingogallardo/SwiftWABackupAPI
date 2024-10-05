//
//  Helpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation

func convertTimestampToDate(timestamp: Any) -> Date {
    if let timestamp = timestamp as? Double {
        return Date(timeIntervalSinceReferenceDate: timestamp)
    } else if let timestamp = timestamp as? Int64 {
        return Date(timeIntervalSinceReferenceDate: Double(timestamp))
    } else if let timestamp = timestamp as? Int {
        return Date(timeIntervalSinceReferenceDate: Double(timestamp))
    }
    return Date(timeIntervalSinceReferenceDate: 0)
}
