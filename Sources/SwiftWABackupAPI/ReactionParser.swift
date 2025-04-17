//
//  ReactionParser.swift
//  SwiftWABackupAPI
//
//  Created by Domingo Gallardo on 17/4/25.
//
//  Parses WhatsApp `receiptInfo` blobs into `Reaction` objects.
//

import Foundation

struct ReactionParser {

    /// Convierte el blob `receiptInfo` en un array de `Reaction`.
    /// Devuelve `nil` si no hay reacciones válidas.
    static func parse(_ data: Data) -> [Reaction]? {
        var reactions: [Reaction] = []
        let dataArray = [UInt8](data)
        var i = 0
        
        while i < dataArray.count {
            // The byte before the emoji indicates the emoji length.
            let emojiLength = Int(dataArray[i])
            if emojiLength <= 28 {
                // Maximum possible length of an emoji is 28 bytes.
                i += 1
                let emojiEndIndex = i + emojiLength
                if emojiEndIndex <= dataArray.count {
                    let emojiData = dataArray[i..<emojiEndIndex]
                    if let emojiStr = String(bytes: emojiData, encoding: .utf8),
                       isSingleEmoji(emojiStr) {
                        // Extract the sender's phone number preceding the emoji.
                        let senderPhone = extractPhoneNumber(from: dataArray,
                                                             endIndex: i-2)
                        reactions.append(
                            Reaction(emoji: emojiStr,
                                     senderPhone: senderPhone ?? "Me"))
                        i = emojiEndIndex - 1
                    }
                }
            } else {
                i += 1
            }
        }
        return reactions.isEmpty ? nil : reactions
    }
    
    /// Checks if a string is a single emoji.
    private static func isSingleEmoji(_ string: String) -> Bool {
        // Checks if the string represents a single emoji character or sequence.
        guard let firstScalar = string.unicodeScalars.first else {
            return false
        }
        return firstScalar.properties.isEmoji &&
            (firstScalar.properties.isEmojiPresentation
             || string.unicodeScalars.contains { $0.properties.isEmojiPresentation })
    }

    private static func extractPhoneNumber(from data: [UInt8], endIndex: Int) -> String? {
         let senderSuffix = "@s.whatsapp.net"
         let suffixData = Array(senderSuffix.utf8)
         var endIndex = endIndex - 1
         
         // Verify the sender suffix is present.
         var suffixEndIndex = suffixData.count - 1
         while suffixEndIndex >= 0 && endIndex >= 0 {
             if data[endIndex] != suffixData[suffixEndIndex] {
                 return nil
             }
             suffixEndIndex -= 1
             endIndex -= 1
         }
         
         // If the sender suffix wasn't fully matched.
         if suffixEndIndex >= 0 {
             return nil
         }
         
         // Extract the phone number.
         var phoneNumberData: [UInt8] = []
         while endIndex >= 0 {
             let char = data[endIndex]
             if char < 48 || char > 57 { // ASCII '0' to '9'
                 break
             }
             phoneNumberData.append(char)
             endIndex -= 1
         }
         
         // If no phone number was found.
         if phoneNumberData.isEmpty {
             return nil
         }
         
         // Convert the phone number data to a string.
         let phoneNumber = String(bytes: phoneNumberData.reversed(), encoding: .utf8)
         return phoneNumber
     }
     
}
