//
//  DatabaseHelpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

func databaseQuestionMarks(count: Int) -> String {
    return Array(repeating: "?", count: count).joined(separator: ", ")
}
