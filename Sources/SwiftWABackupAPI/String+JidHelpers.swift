//
//  String+JidHelpers.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//  Conveniences for dealing with WhatsApp JIDs.
//

import Foundation

public extension String {

    /// Parte *user* antes de la “@”.
    var jidUser: String { components(separatedBy: "@").first ?? self }

    /// Parte *domain* después de la “@”, en minúsculas.
    var jidDomain: String {
        guard let idx = firstIndex(of: "@") else { return "" }
        let dom = self[index(after: idx)...]
        return dom.lowercased()
    }

    /// `true` si es un chat de grupo (“…@g.us”).
    var isGroupJid: Bool { jidDomain == "g.us" }

    /// `true` si es un chat individual (“…@s.whatsapp.net”).
    var isIndividualJid: Bool { jidDomain == "s.whatsapp.net" }

    /// Alias del helper existente para coherencia.
    var extractedPhone: String { jidUser }
}
