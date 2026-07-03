//
//  WABackup+Contacts.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

extension WABackup {
    func buildContactList(
        for chatInfo: ChatInfo,
        from dbQueue: DatabaseQueue,
        whatsAppBackup: ExtractedWhatsAppBackup,
        directory: URL?
    ) throws -> [ContactInfo] {
        var contacts: [ContactInfo] = []
        let ownerPhone = ownerJid?.extractedPhone ?? ""

        var ownerContact = ContactInfo(name: "Me", phone: ownerPhone)
        if let directory {
            ownerContact = try copyContactMedia(for: ownerContact, from: whatsAppBackup, to: directory)
        }
        contacts.append(ownerContact)

        try dbQueue.read { db in
            switch chatInfo.chatType {
            case .individual:
                let otherPhone = chatInfo.contactJid.extractedPhone
                if otherPhone != ownerPhone {
                    var otherContact = ContactInfo(name: chatInfo.name, phone: otherPhone)
                    if let directory {
                        otherContact = try copyContactMedia(for: otherContact, from: whatsAppBackup, to: directory)
                    }
                    contacts.append(otherContact)
                }

            case .group:
                let members = try fetchGroupContactMembers(forChatId: chatInfo.id, from: db)
                var seenPhones = Set(contacts.map(\.phone))

                for member in members {
                    let senderInfo = try fetchGroupMemberInfo(groupMember: member, from: db)
                    guard let phone = senderInfo.senderPhone,
                          phone != ownerPhone,
                          seenPhones.insert(phone).inserted else {
                        continue
                    }

                    var contact = ContactInfo(
                        name: senderInfo.senderName ?? phone,
                        phone: phone
                    )
                    if let directory {
                        contact = try copyContactMedia(for: contact, from: whatsAppBackup, to: directory)
                    }
                    contacts.append(contact)
                }
            }
        }

        return contacts
    }

    func copyContactMedia(
        for contact: ContactInfo,
        from whatsAppBackup: ExtractedWhatsAppBackup,
        to directory: URL?
    ) throws -> ContactInfo {
        var updated = contact
        let prefix = "Media/Profile/\(contact.phone)"
        let files = try whatsAppBackup.fileDetails(containing: prefix)

        let latest = FileUtils.latestFile(for: prefix, fileExtension: "jpg", in: files)
            ?? FileUtils.latestFile(for: prefix, fileExtension: "thumb", in: files)

        if let latest {
            let fileName = latest.filename
            let targetFileName = contact.phone + (fileName.hasSuffix(".jpg") ? ".jpg" : ".thumb")
            try mediaCopier?.copy(sourceURL: latest.sourceURL, named: targetFileName, to: directory)
            updated.photoFilename = targetFileName
        }

        return updated
    }
}
