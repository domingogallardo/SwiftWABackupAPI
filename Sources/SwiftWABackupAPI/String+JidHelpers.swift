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

    /// Returns `true` for LID-based participant identifiers (`...@lid`).
    var isLidJid: Bool { jidDomain == "lid" }

    /// Convenience alias for the extracted JID user portion.
    var extractedPhone: String { jidUser }

    /// Removes bidi control characters and collapses surrounding whitespace.
    ///
    /// WhatsApp sometimes stores chat and participant labels with invisible
    /// directionality marks such as LEFT-TO-RIGHT MARK. The web UI does not
    /// surface those marks, so the API strips them before exposing display text.
    var normalizedWhatsAppDisplayText: String {
        let cleanedScalars = unicodeScalars.filter { !Self.whatsAppIgnoredDisplayScalars.contains($0) }
        let cleaned = String(String.UnicodeScalarView(cleanedScalars))
        let collapsedWhitespace = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let whatsAppIgnoredDisplayScalars: Set<UnicodeScalar> = [
        "\u{200E}", // LEFT-TO-RIGHT MARK
        "\u{200F}", // RIGHT-TO-LEFT MARK
        "\u{202A}", // LEFT-TO-RIGHT EMBEDDING
        "\u{202B}", // RIGHT-TO-LEFT EMBEDDING
        "\u{202C}", // POP DIRECTIONAL FORMATTING
        "\u{202D}", // LEFT-TO-RIGHT OVERRIDE
        "\u{202E}"  // RIGHT-TO-LEFT OVERRIDE
    ]
}
