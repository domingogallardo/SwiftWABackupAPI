//
//  ProfilePushName.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//


import GRDB

struct ProfilePushName {
    let jid: String
    let pushName: String
    
    init(row: Row) {
        self.jid = row["ZJID"] as? String ?? ""
        self.pushName = row["ZPUSHNAME"] as? String ?? ""
    }
}
