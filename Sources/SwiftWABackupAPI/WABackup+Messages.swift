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

            return ChatInfo(
                id: Int(chatSession.id),
                contactJid: chatSession.contactJid,
                name: resolvedChatName(for: chatSession),
                numberMessages: Int(chatSession.messageCounter),
                lastMessageDate: chatSession.lastMessageDate,
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
        let author = resolvedAuthor(
            for: message,
            messageType: messageType,
            participantIdentity: participantIdentity
        )
        let eventActor = resolvedEventActor(
            for: message,
            messageType: messageType,
            participantIdentity: participantIdentity
        )
        let messageText = resolveMessageText(
            for: message,
            messageType: messageType,
            eventActor: eventActor
        )

        var messageInfo = MessageInfo(
            id: Int(message.id),
            chatId: Int(message.chatSessionId),
            message: messageText,
            date: message.date,
            isFromMe: message.isFromMe,
            messageType: messageType.description,
            author: author,
            eventActor: eventActor
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
            return MessageAuthor(
                kind: .participant,
                displayName: normalizedAuthorField(chatSession.partnerName),
                phone: normalizedAuthorField(chatSession.contactJid.extractedPhone),
                jid: normalizedAuthorField(chatSession.contactJid),
                source: .chatSession
            )
        }
    }

    func resolvedAuthor(
        for message: Message,
        messageType: SupportedMessageType,
        participantIdentity: MessageAuthor?
    ) -> MessageAuthor? {
        switch messageType {
        case .status:
            return nil
        default:
            return participantIdentity
        }
    }

    func resolvedEventActor(
        for message: Message,
        messageType: SupportedMessageType,
        participantIdentity: MessageAuthor?
    ) -> MessageAuthor? {
        guard messageType == .status else {
            return nil
        }

        guard let participantIdentity else {
            return nil
        }

        guard statusEventShouldExposeEventActor(message: message, participantIdentity: participantIdentity) else {
            return nil
        }

        return participantIdentity
    }

    func statusEventShouldExposeEventActor(
        message: Message,
        participantIdentity: MessageAuthor
    ) -> Bool {
        guard let eventType = message.groupEventType else {
            return false
        }

        switch eventType {
        case 2:
            if let jid = participantIdentity.jid, jid.isGroupJid {
                return false
            }
            return true
        case 40, 41, 58:
            if let jid = participantIdentity.jid, jid.isGroupJid {
                return false
            }
            return true
        default:
            return false
        }
    }

    func fetchReplyMessageId(for message: Message, from db: Database) throws -> Int64? {
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
            return ReactionParser.parse(reactionsData)
        }

        return nil
    }

    func describeStatusSync(
        for message: Message,
        eventActor: MessageAuthor?
    ) -> String {
        if message.isFromMe {
            return "Status sync from me"
        }

        if let name = eventActor?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Status sync from \(name)"
        }

        if let phone = eventActor?.phone, !phone.isEmpty {
            return "Status sync from \(phone)"
        }

        if let fromJid = message.fromJid, !fromJid.isEmpty {
            if fromJid.isIndividualJid || fromJid.isGroupJid {
                let identifier = fromJid.extractedPhone
                if !identifier.isEmpty {
                    return "Status sync from \(identifier)"
                }
            }

            return "Status sync from \(fromJid)"
        }

        return "Status sync notification"
    }

    func resolveMessageText(
        for message: Message,
        messageType: SupportedMessageType,
        eventActor: MessageAuthor?
    ) -> String? {
        switch messageType {
        case .status:
            guard let eventType = message.groupEventType else {
                return message.text
            }

            switch eventType {
            case 38:
                return "This is a business chat"
            case 2:
                if let current = message.text,
                   !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return current
                }

                return describeStatusSync(for: message, eventActor: eventActor)
            default:
                return message.text
            }
        default:
            return message.text
        }
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
        let senderPhone = jid.extractedPhone

        if let senderName = try ChatSession.fetchChatSessionName(for: jid, from: db) {
            return (senderName, senderPhone)
        } else if let pushName = try ProfilePushName.pushName(for: jid, from: db) {
            return ("~" + pushName, senderPhone)
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
        let phone = normalizedAuthorField(jid.extractedPhone)

        if let senderName = try ChatSession.fetchChatSessionName(for: jid, from: db)
            .flatMap(normalizedAuthorField) {
            return MessageAuthor(
                kind: .participant,
                displayName: senderName,
                phone: phone,
                jid: normalizedJid,
                source: .chatSession
            )
        }

        if let pushName = try ProfilePushName.pushName(for: jid, from: db)
            .flatMap(normalizedAuthorField) {
            return MessageAuthor(
                kind: .participant,
                displayName: "~" + pushName,
                phone: phone,
                jid: normalizedJid,
                source: .pushName
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

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
