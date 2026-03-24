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

    /// User portion before the `@`.
    var jidUser: String { components(separatedBy: "@").first ?? self }

    /// Domain portion after the `@`, lowercased.
    var jidDomain: String {
        guard let idx = firstIndex(of: "@") else { return "" }
        let dom = self[index(after: idx)...]
        return dom.lowercased()
    }

    /// Returns `true` for group chats (`...@g.us`).
    var isGroupJid: Bool { jidDomain == "g.us" }

    /// Returns `true` for individual chats (`...@s.whatsapp.net`).
    var isIndividualJid: Bool { jidDomain == "s.whatsapp.net" }

    /// Convenience alias for the extracted JID user portion.
    var extractedPhone: String { jidUser }
}
