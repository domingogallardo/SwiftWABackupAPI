//
//  MessageInfoTable.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct MessageInfoTable {
    let messageId: Int64
    let receiptInfo: Data?
    
    init(row: Row) {
        self.messageId = row["ZMESSAGE"] as? Int64 ?? 0
        self.receiptInfo = row["ZRECEIPTINFO"] as? Data
    }
}
