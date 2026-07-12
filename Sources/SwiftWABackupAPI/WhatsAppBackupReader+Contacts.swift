//
//  WhatsAppBackupReader+Contacts.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

extension WhatsAppBackupReader {
    func buildContactList(
        for chatInfo: ChatInfo,
        from dbQueue: DatabaseQueue,
        whatsAppBackup: ExtractedWhatsAppBackup,
        directory: URL?,
        progress: WABackupProgressHandler? = nil
    ) throws -> [ContactInfo] {
        var contacts: [ContactInfo] = []
        let ownerPhone = ownerJid?.extractedPhone ?? ""
        let profileFiles = try whatsAppBackup.allProfileFileDetails()

        reportProgress(
            progress,
            phase: .buildingContacts,
            completedUnitCount: 0,
            unit: .contacts,
            currentItem: chatInfo.name
        )

        let ownerContact = try resolveContactMedia(
            for: ContactInfo(name: "Me", phone: ownerPhone),
            from: profileFiles,
            in: whatsAppBackup,
            to: directory,
            progress: progress
        )
        contacts.append(ownerContact)

        try dbQueue.read { db in
            switch chatInfo.chatType {
            case .individual:
                let otherPhone = chatInfo.contactJid.extractedPhone
                let totalContacts = otherPhone == ownerPhone ? 1 : 2
                reportProgress(
                    progress,
                    phase: .buildingContacts,
                    completedUnitCount: 1,
                    totalUnitCount: totalContacts,
                    unit: .contacts,
                    currentItem: ownerPhone
                )

                if otherPhone != ownerPhone {
                    let otherContact = try resolveContactMedia(
                        for: ContactInfo(name: chatInfo.name, phone: otherPhone),
                        from: profileFiles,
                        in: whatsAppBackup,
                        to: directory,
                        progress: progress
                    )
                    contacts.append(otherContact)
                    reportProgress(
                        progress,
                        phase: .buildingContacts,
                        completedUnitCount: 2,
                        totalUnitCount: totalContacts,
                        unit: .contacts,
                        currentItem: otherPhone
                    )
                }

            case .group:
                let members = try fetchGroupContactMembers(forChatId: chatInfo.id, from: db)
                var seenPhones = Set(contacts.map(\.phone))
                let totalCandidates = members.count + 1
                reportProgress(
                    progress,
                    phase: .buildingContacts,
                    completedUnitCount: 1,
                    totalUnitCount: totalCandidates,
                    unit: .contacts,
                    currentItem: ownerPhone
                )

                for (index, member) in members.enumerated() {
                    let senderInfo = try fetchGroupMemberInfo(groupMember: member, from: db)
                    let completed = index + 2
                    guard let phone = senderInfo.senderPhone else {
                        reportProgress(
                            progress,
                            phase: .buildingContacts,
                            completedUnitCount: completed,
                            totalUnitCount: totalCandidates,
                            unit: .contacts,
                            currentItem: String(member.id)
                        )
                        continue
                    }

                    guard phone != ownerPhone,
                          seenPhones.insert(phone).inserted else {
                        reportProgress(
                            progress,
                            phase: .buildingContacts,
                            completedUnitCount: completed,
                            totalUnitCount: totalCandidates,
                            unit: .contacts,
                            currentItem: phone
                        )
                        continue
                    }

                    let contact = try resolveContactMedia(
                        for: ContactInfo(
                            name: senderInfo.senderName ?? phone,
                            phone: phone
                        ),
                        from: profileFiles,
                        in: whatsAppBackup,
                        to: directory,
                        progress: progress
                    )
                    contacts.append(contact)
                    reportProgress(
                        progress,
                        phase: .buildingContacts,
                        completedUnitCount: completed,
                        totalUnitCount: totalCandidates,
                        unit: .contacts,
                        currentItem: phone
                    )
                }
            }
        }

        return contacts
    }

    func resolveContactMedia(
        for contact: ContactInfo,
        from profileFiles: [WhatsAppFileDetails],
        in whatsAppBackup: ExtractedWhatsAppBackup,
        to directory: URL?,
        progress: WABackupProgressHandler? = nil
    ) throws -> ContactInfo {
        var updated = contact
        let prefix = "Media/Profile/\(contact.phone)"

        let latest = FileUtils.latestFile(for: prefix, fileExtension: "jpg", in: profileFiles)
            ?? FileUtils.latestFile(for: prefix, fileExtension: "thumb", in: profileFiles)

        if let latest {
            let fileName = latest.filename
            let targetFileName = contact.phone + (fileName.hasSuffix(".jpg") ? ".jpg" : ".thumb")
            updated.photoReference = try whatsAppBackup.mediaReference(sourceURL: latest.sourceURL)

            if let directory {
                try mediaCopier.copy(
                    sourceURL: latest.sourceURL,
                    named: targetFileName,
                    to: directory,
                    progress: progress
                )
                updated.photoFilename = targetFileName
            }
        }

        return updated
    }
}
