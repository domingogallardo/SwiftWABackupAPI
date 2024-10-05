//
//  MediaItem.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 3/10/24.
//

import Foundation
import GRDB

struct MediaItem {
    let id: Int64
    let localPath: String?
    let metadata: Data?
    let title: String?
    let movieDuration: Int64?
    let latitude: Double?
    let longitude: Double?
    
    init(row: Row) {
        self.id = row["Z_PK"] as? Int64 ?? 0
        self.localPath = row["ZMEDIALOCALPATH"] as? String
        self.metadata = row["ZMETADATA"] as? Data
        self.title = row["ZTITLE"] as? String
        self.movieDuration = row["ZMOVIEDURATION"] as? Int64
        self.latitude = row["ZLATITUDE"] as? Double
        self.longitude = row["ZLONGITUDE"] as? Double
    }
}
