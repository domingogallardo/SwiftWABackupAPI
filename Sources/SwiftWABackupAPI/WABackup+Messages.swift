//
//  WABackup+Messages.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WABackup {
    /// Retrieves a full chat export using the legacy tuple payload.
    func getChat(chatId: Int, directoryToSaveMedia directory: URL?) throws -> ChatDump {
        guard let dbQueue = chatDatabase, let iPhoneBackup = iPhoneBackup else {
            throw DatabaseErrorWA.connection(DatabaseError(message: "Database or backup not found"))
        }

        let chatInfo = try fetchChatInfo(id: chatId, from: dbQueue)
        let messages = try fetchMessagesFromDatabase(chatId: chatId, from: dbQueue)
        let processedMessages = try processMessages(
            messages,
            chatType: chatInfo.chatType,
            directoryToSaveMedia: directory,
            iPhoneBackup: iPhoneBackup,
            from: dbQueue
        )
        let contacts = try buildContactList(
            for: chatInfo,
            from: dbQueue,
            iPhoneBackup: iPhoneBackup,
            directory: directory
        )

        return (chatInfo, processedMessages, contacts)
    }

    /// Retrieves a full chat export wrapped in an `Encodable` payload.
    func getChatPayload(chatId: Int, directoryToSaveMedia directory: URL?) throws -> ChatDumpPayload {
        try ChatDumpPayload(getChat(chatId: chatId, directoryToSaveMedia: directory))
    }
}

extension WABackup {
    func fetchChatInfo(id: Int, from dbQueue: DatabaseQueue) throws -> ChatInfo {
        try dbQueue.performRead { db in
            let chatSession = try ChatSession.fetchChat(byId: id, from: db)
            let publicSummary = try Message.fetchPublicSummary(forChatId: id, from: db)

            return ChatInfo(
                id: Int(chatSession.id),
                contactJid: chatSession.contactJid,
                name: resolvedChatName(for: chatSession),
                numberMessages: Int(publicSummary.count),
                lastMessageDate: publicSummary.lastMessageDate ?? chatSession.lastMessageDate,
                isArchived: chatSession.isArchived
            )
        }
    }

    func fetchMessagesFromDatabase(chatId: Int, from dbQueue: DatabaseQueue) throws -> [Message] {
        try dbQueue.performRead { db in
            try Message.fetchMessages(forChatId: chatId, from: db)
        }
    }

    func processMessages(
        _ messages: [Message],
        chatType: ChatInfo.ChatType,
        directoryToSaveMedia: URL?,
        iPhoneBackup: IPhoneBackup,
        from dbQueue: DatabaseQueue
    ) throws -> [MessageInfo] {
        var messagesInfo: [MessageInfo] = []

        try dbQueue.read { db in
            for message in messages {
                let messageInfo = try processSingleMessage(
                    message,
                    chatType: chatType,
                    directoryToSaveMedia: directoryToSaveMedia,
                    iPhoneBackup: iPhoneBackup,
                    from: db
                )
                messagesInfo.append(messageInfo)
            }
        }

        return messagesInfo
    }

    func processSingleMessage(
        _ message: Message,
        chatType: ChatInfo.ChatType,
        directoryToSaveMedia: URL?,
        iPhoneBackup: IPhoneBackup,
        from db: Database
    ) throws -> MessageInfo {
        guard let messageType = SupportedMessageType(rawValue: message.messageType) else {
            throw DomainError.unexpected(reason: "Unsupported message type")
        }

        let participantIdentity = try resolveParticipantIdentity(for: message, chatType: chatType, from: db)

        var messageInfo = MessageInfo(
            id: Int(message.id),
            chatId: Int(message.chatSessionId),
            message: message.text,
            date: message.date,
            isFromMe: message.isFromMe,
            messageType: messageType.description,
            author: participantIdentity
        )

        if let replyMessageId = try fetchReplyMessageId(for: message, from: db) {
            messageInfo.replyTo = Int(replyMessageId)
        }

        if let mediaInfo = try handleMedia(
            for: message,
            directoryToSaveMedia: directoryToSaveMedia,
            iPhoneBackup: iPhoneBackup,
            from: db
        ) {
            messageInfo.mediaFilename = mediaInfo.mediaFilename
            messageInfo.caption = mediaInfo.caption
            messageInfo.seconds = mediaInfo.seconds
            messageInfo.latitude = mediaInfo.latitude
            messageInfo.longitude = mediaInfo.longitude
            messageInfo.error = mediaInfo.error
        }

        messageInfo.reactions = try fetchReactions(forMessageId: Int(message.id), from: db)
        return messageInfo
    }

    func resolveParticipantIdentity(
        for message: Message,
        chatType: ChatInfo.ChatType,
        from db: Database
    ) throws -> MessageAuthor? {
        if message.isFromMe {
            return MessageAuthor(
                kind: .me,
                displayName: "Me",
                phone: normalizedAuthorField(ownerJid?.extractedPhone),
                jid: normalizedAuthorField(ownerJid),
                source: .owner
            )
        }

        switch chatType {
        case .group:
            if let memberId = message.groupMemberId,
               let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
                return try makeParticipantAuthor(
                    jid: groupMember.memberJid,
                    contactNameGroupMember: groupMember.contactName,
                    fallbackSource: .groupMember,
                    from: db
                )
            }

            if let fromJid = normalizedAuthorField(message.fromJid) {
                return try makeParticipantAuthor(
                    jid: fromJid,
                    contactNameGroupMember: nil,
                    fallbackSource: .messageJid,
                    from: db
                )
            }

            return nil

        case .individual:
            let chatSession = try ChatSession.fetchChat(byId: Int(message.chatSessionId), from: db)
            if let displayName = normalizedAuthorField(chatSession.partnerName) {
                return MessageAuthor(
                    kind: .participant,
                    displayName: displayName,
                    phone: resolvedPhone(for: chatSession.contactJid),
                    jid: resolvedParticipantJid(for: chatSession.contactJid),
                    source: .chatSession
                )
            }

            if let addressBookAuthor = makeAddressBookAuthor(for: chatSession.contactJid) {
                return addressBookAuthor
            }

            return MessageAuthor(
                kind: .participant,
                displayName: nil,
                phone: resolvedPhone(for: chatSession.contactJid),
                jid: resolvedParticipantJid(for: chatSession.contactJid),
                source: .chatSession
            )
        }
    }

    func fetchReplyMessageId(for message: Message, from db: Database) throws -> Int64? {
        if let parentMessageId = message.parentMessageId {
            return parentMessageId
        }

        if let mediaItemId = message.mediaItemId,
           let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let stanzaId = mediaItem.extractReplyStanzaId() {
            return try Message.fetchMessageId(byStanzaId: stanzaId, from: db)
        }

        return nil
    }

    func handleMedia(
        for message: Message,
        directoryToSaveMedia: URL?,
        iPhoneBackup: IPhoneBackup,
        from db: Database
    ) throws -> (
        mediaFilename: String?,
        caption: String?,
        seconds: Int?,
        latitude: Double?,
        longitude: Double?,
        error: String?
    )? {
        guard let mediaItemId = message.mediaItemId else {
            return nil
        }

        let mediaFilename = try fetchMediaFilename(
            forMediaItem: mediaItemId,
            from: iPhoneBackup,
            toDirectory: directoryToSaveMedia,
            from: db
        )
        let caption = try fetchCaption(mediaItemId: mediaItemId, from: db)

        let seconds: Int?
        let latitude: Double?
        let longitude: Double?

        if let messageType = SupportedMessageType(rawValue: message.messageType),
           messageType == .video || messageType == .audio {
            seconds = try fetchDuration(mediaItemId: mediaItemId, from: db)
        } else {
            seconds = nil
        }

        if let messageType = SupportedMessageType(rawValue: message.messageType),
           messageType == .location {
            let location = try fetchLocation(mediaItemId: mediaItemId, from: db)
            latitude = location.0
            longitude = location.1
        } else {
            latitude = nil
            longitude = nil
        }

        return (mediaFilename, caption, seconds, latitude, longitude, nil)
    }

    func fetchMediaFilename(
        forMediaItem mediaItemId: Int64,
        from iPhoneBackup: IPhoneBackup,
        toDirectory directoryURL: URL?,
        from db: Database
    ) throws -> String? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let mediaLocalPath = mediaItem.localPath,
           let hashFile = try? iPhoneBackup.fetchWAFileHash(endsWith: mediaLocalPath) {
            let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
            try mediaCopier?.copy(hash: hashFile, named: fileName, to: directoryURL)
            return fileName
        }

        return nil
    }

    func fetchGroupMemberInfo(
        memberId: Int64,
        from db: Database
    ) throws -> (senderName: String?, senderPhone: String?)? {
        if let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
            return try obtainSenderInfo(
                jid: groupMember.memberJid,
                contactNameGroupMember: groupMember.contactName,
                from: db
            )
        }

        return nil
    }

    func fetchDuration(mediaItemId: Int64, from db: Database) throws -> Int? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let duration = mediaItem.movieDuration {
            return Int(duration)
        }

        return nil
    }

    func fetchReactions(forMessageId messageId: Int, from db: Database) throws -> [Reaction]? {
        if let messageInfo = try MessageInfoTable.fetch(by: messageId, from: db),
           let reactionsData = messageInfo.receiptInfo {
            return parseReactions(from: reactionsData, from: db)
        }

        return try fetchDuplicateDocumentReactions(forMessageId: messageId, from: db)
    }

    func parseReactions(from reactionsData: Data, from db: Database) -> [Reaction]? {
        ReactionParser.parse(reactionsData) { [self] senderJid in
            try? resolveReactionAuthor(for: senderJid, from: db)
        }
    }

    func fetchDuplicateDocumentReactions(forMessageId messageId: Int, from db: Database) throws -> [Reaction]? {
        guard let message = try Message.fetch(by: Int64(messageId), from: db),
              message.messageType == SupportedMessageType.doc.rawValue,
              let currentText = normalizedAuthorField(message.text) else {
            return nil
        }

        let normalizedCurrentName = normalizedDuplicateDocumentName(currentText)
        let searchWindowStart = message.date.addingTimeInterval(-12 * 60 * 60).timeIntervalSinceReferenceDate
        let searchWindowEnd = message.date.timeIntervalSinceReferenceDate

        let candidateRows = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM \(Message.tableName)
                WHERE ZCHATSESSION = ?
                  AND ZMESSAGETYPE = ?
                  AND Z_PK <> ?
                  AND ZTEXT IS NOT NULL
                  AND ZMESSAGEDATE BETWEEN ? AND ?
                ORDER BY ZMESSAGEDATE DESC
                LIMIT 25
                """,
            arguments: [
                message.chatSessionId,
                message.messageType,
                message.id,
                searchWindowStart,
                searchWindowEnd
            ]
        )

        for candidate in candidateRows.map(Message.init(row:)) {
            guard candidate.groupMemberId == message.groupMemberId,
                  candidate.isFromMe == message.isFromMe,
                  let candidateText = normalizedAuthorField(candidate.text),
                  normalizedDuplicateDocumentName(candidateText) == normalizedCurrentName,
                  currentText != candidateText,
                  hasDuplicateDocumentCopySuffix(currentText) || hasDuplicateDocumentCopySuffix(candidateText),
                  let messageInfo = try MessageInfoTable.fetch(by: Int(candidate.id), from: db),
                  let receiptInfo = messageInfo.receiptInfo,
                  let reactions = parseReactions(from: receiptInfo, from: db) else {
                continue
            }

            return reactions
        }

        return nil
    }

    func resolveReactionAuthor(for senderJid: String, from db: Database) throws -> MessageAuthor? {
        guard let normalizedJid = normalizedAuthorField(senderJid) else {
            return nil
        }

        if normalizedJid == normalizedAuthorField(ownerJid) {
            return MessageAuthor(
                kind: .me,
                displayName: "Me",
                phone: normalizedAuthorField(ownerJid?.extractedPhone),
                jid: normalizedAuthorField(ownerJid),
                source: .owner
            )
        }

        return try makeParticipantAuthor(
            jid: normalizedJid,
            contactNameGroupMember: nil,
            fallbackSource: .messageJid,
            from: db
        )
    }

    func fetchCaption(mediaItemId: Int64, from db: Database) throws -> String? {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db),
           let caption = mediaItem.title,
           !caption.isEmpty {
            return caption
        }

        return nil
    }

    func fetchLocation(mediaItemId: Int64, from db: Database) throws -> (Double, Double) {
        if let mediaItem = try MediaItem.fetchMediaItem(byId: mediaItemId, from: db) {
            return (mediaItem.latitude ?? 0.0, mediaItem.longitude ?? 0.0)
        }

        return (0.0, 0.0)
    }

    func obtainSenderInfo(
        jid: String,
        contactNameGroupMember: String?,
        from db: Database
    ) throws -> (senderName: String?, senderPhone: String?) {
        let senderPhone = resolvedPhone(for: jid)
        let chatSessionName = try ChatSession.fetchChatSessionName(for: jid, from: db)
            .flatMap(normalizedAuthorField)

        if let senderName = chatSessionName,
           !isPhoneLikeDisplayLabel(senderName, resolvedPhone: senderPhone) {
            return (senderName, senderPhone)
        } else if let addressBookContact = addressBookIndex?.contact(for: jid),
                  let displayName = normalizedAuthorField(addressBookContact.bestDisplayName) {
            return (
                displayName,
                normalizedAuthorField(addressBookContact.bestResolvedPhone) ?? senderPhone
            )
        } else if let lidAccount = lidAccountIndex?.account(for: jid) {
            let profileDisplayName = try ProfilePushName.pushName(for: jid, from: db)
                .flatMap(normalizedAuthorField)
            return (
                profileDisplayName,
                normalizedAuthorField(lidAccount.normalizedPhoneNumber) ?? senderPhone
            )
        } else if let linkedPhoneJid = linkedPhoneJid(for: jid) {
            return (nil, normalizedAuthorField(linkedPhoneJid.extractedPhone))
        } else if let pushName = try ProfilePushName.pushName(for: jid, from: db) {
            return (normalizedAuthorField(pushName), senderPhone)
        } else if let chatSessionName {
            return (chatSessionName, senderPhone)
        } else {
            return (contactNameGroupMember, senderPhone)
        }
    }

    func makeParticipantAuthor(
        jid: String,
        contactNameGroupMember: String?,
        fallbackSource: MessageAuthor.Source,
        from db: Database
    ) throws -> MessageAuthor {
        let normalizedJid = normalizedAuthorField(jid)
        let phone = resolvedPhone(for: jid)
        let linkedPhoneJid = linkedPhoneJid(for: jid) ?? lidAccountIndex?.phoneJid(for: jid)
        let chatSessionDisplayName = try ChatSession.fetchChatSessionName(for: jid, from: db)
            .flatMap(normalizedAuthorField)
        let profileDisplayName = try ProfilePushName.pushName(for: jid, from: db)
            .flatMap(whatsAppProfileDisplayName)
        let linkedPhoneDisplayName = try linkedPhoneJid
            .flatMap { try ProfilePushName.pushName(for: $0, from: db) }
            .flatMap(whatsAppProfileDisplayName)

        if let senderName = chatSessionDisplayName,
           !isPhoneLikeDisplayLabel(senderName, resolvedPhone: phone) {
            return MessageAuthor(
                kind: .participant,
                displayName: senderName,
                phone: phone,
                jid: normalizedJid,
                source: .chatSession
            )
        }

        if let addressBookAuthor = makeAddressBookAuthor(for: jid) {
            return addressBookAuthor
        }

        if let lidAccountAuthor = makeLidAccountAuthor(
            for: jid,
            profileDisplayName: profileDisplayName ?? linkedPhoneDisplayName
        ) {
            return lidAccountAuthor
        }

        if let linkedPhoneJid {
            return MessageAuthor(
                kind: .participant,
                displayName: profileDisplayName ?? linkedPhoneDisplayName,
                phone: normalizedAuthorField(linkedPhoneJid.extractedPhone),
                jid: normalizedAuthorField(linkedPhoneJid),
                source: .pushNamePhoneJid
            )
        }

        if let pushName = profileDisplayName {
            return MessageAuthor(
                kind: .participant,
                displayName: pushName,
                phone: phone,
                jid: normalizedJid,
                source: .pushName
            )
        }

        if let chatSessionDisplayName {
            return MessageAuthor(
                kind: .participant,
                displayName: chatSessionDisplayName,
                phone: phone,
                jid: normalizedJid,
                source: .chatSession
            )
        }

        return MessageAuthor(
            kind: .participant,
            displayName: normalizedAuthorField(contactNameGroupMember),
            phone: phone,
            jid: normalizedJid,
            source: fallbackSource
        )
    }

    func normalizedAuthorField(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value.normalizedWhatsAppDisplayText
        return normalized.isEmpty ? nil : normalized
    }

    func isPhoneLikeDisplayLabel(_ value: String?, resolvedPhone: String?) -> Bool {
        guard let normalized = normalizedAuthorField(value) else {
            return false
        }

        let hasLetters = normalized.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if hasLetters {
            return false
        }

        let digitsOnly = normalized.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
        let digitString = String(String.UnicodeScalarView(digitsOnly))

        guard digitString.count >= 7 else {
            return false
        }

        if let resolvedPhone {
            let normalizedPhoneDigits = resolvedPhone.unicodeScalars
                .filter { CharacterSet.decimalDigits.contains($0) }
            let normalizedPhone = String(String.UnicodeScalarView(normalizedPhoneDigits))
            return digitString == normalizedPhone
        }

        return normalized.range(of: #"^\+?[\d\s().-]+$"#, options: .regularExpression) != nil
    }

    func whatsAppProfileDisplayName(_ value: String?) -> String? {
        guard let normalized = normalizedAuthorField(value) else {
            return nil
        }

        return "~\(normalized)"
    }

    func resolvedPhone(for jid: String?) -> String? {
        guard let jid else {
            return nil
        }

        if let addressBookPhone = addressBookIndex?.contact(for: jid)?.bestResolvedPhone {
            return normalizedAuthorField(addressBookPhone)
        }

        if let lidAccountPhone = lidAccountIndex?.phoneNumber(for: jid) {
            return normalizedAuthorField(lidAccountPhone)
        }

        if let linkedPhoneJid = linkedPhoneJid(for: jid) {
            return normalizedAuthorField(linkedPhoneJid.extractedPhone)
        }

        guard jid.isIndividualJid else {
            return nil
        }

        return normalizedAuthorField(jid.extractedPhone)
    }

    func linkedPhoneJid(for jid: String?) -> String? {
        guard let jid else {
            return nil
        }

        return pushNamePhoneJidIndex?.linkedPhoneJid(for: jid)
    }

    func resolvedParticipantJid(for jid: String?) -> String? {
        guard let jid else {
            return nil
        }

        if let addressBookJid = addressBookIndex?.contact(for: jid)?.bestResolvedJid {
            return normalizedAuthorField(addressBookJid)
        }

        if let lidAccountPhoneJid = lidAccountIndex?.phoneJid(for: jid) {
            return normalizedAuthorField(lidAccountPhoneJid)
        }

        if let linkedPhoneJid = linkedPhoneJid(for: jid) {
            return normalizedAuthorField(linkedPhoneJid)
        }

        return normalizedAuthorField(jid)
    }

    func makeAddressBookAuthor(for jid: String) -> MessageAuthor? {
        guard let contact = addressBookIndex?.contact(for: jid),
              let displayName = normalizedAuthorField(contact.bestDisplayName) else {
            return nil
        }

        let resolvedJid = normalizedAuthorField(contact.bestResolvedJid) ?? normalizedAuthorField(jid)
        let resolvedPhone = normalizedAuthorField(contact.bestResolvedPhone)
            ?? (jid.isIndividualJid ? normalizedAuthorField(jid.extractedPhone) : nil)

        return MessageAuthor(
            kind: .participant,
            displayName: displayName,
            phone: resolvedPhone,
            jid: resolvedJid,
            source: .addressBook
        )
    }

    func makeLidAccountAuthor(for jid: String, profileDisplayName: String?) -> MessageAuthor? {
        guard let lidAccount = lidAccountIndex?.account(for: jid),
              let resolvedPhone = normalizedAuthorField(lidAccount.normalizedPhoneNumber) else {
            return nil
        }

        return MessageAuthor(
            kind: .participant,
            displayName: profileDisplayName,
            phone: resolvedPhone,
            jid: resolvedParticipantJid(for: jid),
            source: .lidAccount
        )
    }
}

private extension String {
    var duplicateDocumentCopySuffixRange: Range<String.Index>? {
        if let range = range(of: #" \(\d+\)$"#, options: .regularExpression) {
            return range
        }

        return range(of: #"-\d+$"#, options: .regularExpression)
    }
}

private func normalizedDuplicateDocumentName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let dotIndex = trimmed.lastIndex(of: "."), dotIndex > trimmed.startIndex else {
        return trimmed
    }

    let basename = String(trimmed[..<dotIndex])
    let extensionSuffix = String(trimmed[dotIndex...])

    if let suffixRange = basename.duplicateDocumentCopySuffixRange {
        return String(basename[..<suffixRange.lowerBound]) + extensionSuffix
    }

    return trimmed
}

private func hasDuplicateDocumentCopySuffix(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let dotIndex = trimmed.lastIndex(of: "."), dotIndex > trimmed.startIndex else {
        return false
    }

    let basename = String(trimmed[..<dotIndex])
    return basename.duplicateDocumentCopySuffixRange != nil
}
