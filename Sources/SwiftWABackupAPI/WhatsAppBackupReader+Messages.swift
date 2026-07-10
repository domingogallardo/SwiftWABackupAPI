//
//  WhatsAppBackupReader+Messages.swift
//  SwiftWABackupAPI
//

import Foundation
import GRDB

public extension WhatsAppBackupReader {
    /// Retrieves a full chat export.
    func getChat(
        chatId: Int,
        directoryToSaveMedia directory: URL? = nil,
        progress: WABackupProgressHandler? = nil
    ) throws -> ChatDumpPayload {
        reportProgress(
            progress,
            phase: .exportingChat,
            completedUnitCount: 0,
            totalUnitCount: 4,
            unit: .phases,
            currentItem: "chat \(chatId)"
        )

        let chatInfo = try fetchChatInfo(id: chatId, from: chatDatabase)
        reportProgress(
            progress,
            phase: .exportingChat,
            completedUnitCount: 1,
            totalUnitCount: 4,
            unit: .phases,
            currentItem: chatInfo.name
        )

        reportProgress(
            progress,
            phase: .loadingMessages,
            completedUnitCount: 0,
            unit: .messages,
            currentItem: chatInfo.name
        )
        let messages = try fetchMessagesFromDatabase(chatId: chatId, from: chatDatabase)
        reportProgress(
            progress,
            phase: .loadingMessages,
            completedUnitCount: messages.count,
            totalUnitCount: messages.count,
            unit: .messages,
            currentItem: chatInfo.name
        )

        let exportContext = try chatDatabase.performRead { db in
            try ChatExportContext.load(chatId: chatId, messages: messages, from: db)
        }
        let exportState = ChatExportState(context: exportContext)

        let processedMessages = try processMessages(
            messages,
            chatType: chatInfo.chatType,
            directoryToSaveMedia: directory,
            whatsAppBackup: whatsAppBackup,
            state: exportState,
            progress: progress
        )
        reportProgress(
            progress,
            phase: .exportingChat,
            completedUnitCount: 2,
            totalUnitCount: 4,
            unit: .phases,
            currentItem: chatInfo.name
        )

        let contacts = try buildContactList(
            for: chatInfo,
            from: chatDatabase,
            whatsAppBackup: whatsAppBackup,
            directory: directory,
            progress: progress
        )
        reportProgress(
            progress,
            phase: .exportingChat,
            completedUnitCount: 3,
            totalUnitCount: 4,
            unit: .phases,
            currentItem: chatInfo.name
        )

        let payload = ChatDumpPayload(
            chatInfo: chatInfo,
            messages: processedMessages,
            contacts: contacts
        )

        reportProgress(
            progress,
            phase: .exportingChat,
            completedUnitCount: 4,
            totalUnitCount: 4,
            unit: .phases,
            currentItem: chatInfo.name
        )
        reportProgress(
            progress,
            phase: .completed,
            completedUnitCount: 1,
            totalUnitCount: 1,
            unit: .phases,
            currentItem: "getChat"
        )
        return payload
    }
}

extension WhatsAppBackupReader {
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
        whatsAppBackup: ExtractedWhatsAppBackup,
        state: ChatExportState,
        progress: WABackupProgressHandler? = nil
    ) throws -> [MessageInfo] {
        var messagesInfo: [MessageInfo] = []
        messagesInfo.reserveCapacity(messages.count)

        reportProgress(
            progress,
            phase: .processingMessages,
            completedUnitCount: 0,
            totalUnitCount: messages.count,
            unit: .messages
        )

        for (index, message) in messages.enumerated() {
            let messageInfo = try processSingleMessage(
                message,
                chatType: chatType,
                directoryToSaveMedia: directoryToSaveMedia,
                whatsAppBackup: whatsAppBackup,
                state: state,
                progress: progress
            )
            messagesInfo.append(messageInfo)
            reportProgress(
                progress,
                phase: .processingMessages,
                completedUnitCount: index + 1,
                totalUnitCount: messages.count,
                unit: .messages,
                currentItem: String(message.id)
            )
        }

        return messagesInfo
    }

    func processSingleMessage(
        _ message: Message,
        chatType: ChatInfo.ChatType,
        directoryToSaveMedia: URL?,
        whatsAppBackup: ExtractedWhatsAppBackup,
        state: ChatExportState,
        progress: WABackupProgressHandler? = nil
    ) throws -> MessageInfo {
        guard let messageType = SupportedMessageType(rawValue: message.messageType) else {
            throw DomainError.unexpected(reason: "Unsupported message type")
        }

        let participantIdentity = resolveParticipantIdentity(for: message, chatType: chatType, state: state)

        var messageInfo = MessageInfo(
            id: Int(message.id),
            chatId: Int(message.chatSessionId),
            message: message.text,
            date: message.date,
            isFromMe: message.isFromMe,
            messageType: messageType.description,
            author: participantIdentity
        )

        if let replyMessageId = fetchReplyMessageId(for: message, context: state.context) {
            messageInfo.replyTo = Int(replyMessageId)
        }

        if let mediaInfo = try handleMedia(
            for: message,
            directoryToSaveMedia: directoryToSaveMedia,
            whatsAppBackup: whatsAppBackup,
            context: state.context,
            progress: progress
        ) {
            messageInfo.mediaFilename = mediaInfo.mediaFilename
            messageInfo.caption = mediaInfo.caption
            messageInfo.seconds = mediaInfo.seconds
            messageInfo.latitude = mediaInfo.latitude
            messageInfo.longitude = mediaInfo.longitude
            messageInfo.error = mediaInfo.error
        }

        messageInfo.reactions = fetchReactions(for: message, state: state)
        return messageInfo
    }

    func resolveParticipantIdentity(
        for message: Message,
        chatType: ChatInfo.ChatType,
        state: ChatExportState
    ) -> MessageAuthor? {
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
               let groupMember = state.context.groupMembersById[memberId] {
                return makeParticipantAuthor(
                    jid: groupMember.memberJid,
                    contactNameGroupMember: groupMember.contactName,
                    fallbackSource: .groupMember,
                    state: state
                )
            }

            if let fromJid = normalizedAuthorField(message.fromJid) {
                return makeParticipantAuthor(
                    jid: fromJid,
                    contactNameGroupMember: nil,
                    fallbackSource: .messageJid,
                    state: state
                )
            }

            return nil

        case .individual:
            let chatSession = state.context.chatSession
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

    func fetchReplyMessageId(for message: Message, context: ChatExportContext) -> Int64? {
        if let parentMessageId = message.parentMessageId {
            return parentMessageId
        }

        if let mediaItemId = message.mediaItemId,
           let mediaItem = context.mediaItemsById[mediaItemId],
           let stanzaId = mediaItem.extractReplyStanzaId() {
            return context.messageIdsByStanzaId[stanzaId]
        }

        return nil
    }

    func handleMedia(
        for message: Message,
        directoryToSaveMedia: URL?,
        whatsAppBackup: ExtractedWhatsAppBackup,
        context: ChatExportContext,
        progress: WABackupProgressHandler? = nil
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

        guard let mediaItem = context.mediaItemsById[mediaItemId] else {
            return nil
        }

        let mediaFilename = try fetchMediaFilename(
            forMediaItem: mediaItem,
            from: whatsAppBackup,
            toDirectory: directoryToSaveMedia,
            progress: progress
        )
        let caption = mediaItem.title.flatMap { $0.isEmpty ? nil : $0 }

        let seconds: Int?
        let latitude: Double?
        let longitude: Double?

        if let messageType = SupportedMessageType(rawValue: message.messageType),
           messageType == .video || messageType == .audio {
            seconds = mediaItem.movieDuration.map(Int.init)
        } else {
            seconds = nil
        }

        if let messageType = SupportedMessageType(rawValue: message.messageType),
           messageType == .location {
            latitude = mediaItem.latitude
            longitude = mediaItem.longitude
        } else {
            latitude = nil
            longitude = nil
        }

        return (mediaFilename, caption, seconds, latitude, longitude, nil)
    }

    func fetchMediaFilename(
        forMediaItem mediaItem: MediaItem,
        from whatsAppBackup: ExtractedWhatsAppBackup,
        toDirectory directoryURL: URL?,
        progress: WABackupProgressHandler? = nil
    ) throws -> String? {
        if let mediaLocalPath = mediaItem.localPath,
           let sourceURL = try? whatsAppBackup.fileURL(endingWith: mediaLocalPath) {
            let fileName = URL(fileURLWithPath: mediaLocalPath).lastPathComponent
            try mediaCopier.copy(sourceURL: sourceURL, named: fileName, to: directoryURL, progress: progress)
            return fileName
        }

        return nil
    }

    func fetchGroupMemberInfo(
        memberId: Int64,
        from db: Database
    ) throws -> (senderName: String?, senderPhone: String?)? {
        if let groupMember = try GroupMember.fetchGroupMember(byId: memberId, from: db) {
            return try fetchGroupMemberInfo(groupMember: groupMember, from: db)
        }

        return nil
    }

    func fetchGroupMemberInfo(
        groupMember: GroupMember,
        from db: Database
    ) throws -> (senderName: String?, senderPhone: String?) {
        try obtainSenderInfo(
            jid: groupMember.memberJid,
            contactNameGroupMember: groupMember.contactName,
            from: db
        )
    }

    func fetchGroupContactMembers(
        forChatId chatId: Int,
        from db: Database
    ) throws -> [GroupMember] {
        let activeMembers = try GroupMember.fetchActiveGroupMembers(forChatId: chatId, from: db)
        let messageMemberIds = try GroupMember.fetchGroupMemberIds(forChatId: chatId, from: db)
        let messageMembers = try messageMemberIds.compactMap { memberId in
            try GroupMember.fetchGroupMember(byId: memberId, from: db)
        }

        var members = activeMembers
        var seenMemberIds = Set(activeMembers.map(\.id))
        for member in messageMembers where seenMemberIds.insert(member.id).inserted {
            members.append(member)
        }
        return members
    }

    func fetchReactions(for message: Message, state: ChatExportState) -> [Reaction]? {
        if let messageInfo = state.context.messageInfoByMessageId[message.id],
           let reactionsData = messageInfo.receiptInfo {
            return parseReactions(from: reactionsData, state: state)
        }

        return fetchDuplicateDocumentReactions(for: message, state: state)
    }

    func parseReactions(from reactionsData: Data, state: ChatExportState) -> [Reaction]? {
        ReactionParser.parse(reactionsData) { [self] senderJid in
            resolveReactionAuthor(for: senderJid, state: state)
        }
    }

    func fetchDuplicateDocumentReactions(
        for message: Message,
        state: ChatExportState
    ) -> [Reaction]? {
        guard message.messageType == SupportedMessageType.doc.rawValue,
              let currentText = normalizedAuthorField(message.text) else {
            return nil
        }

        let normalizedCurrentName = normalizedDuplicateDocumentName(currentText)

        for candidate in state.context.duplicateDocumentCandidates(for: message) {
            guard candidate.groupMemberId == message.groupMemberId,
                  candidate.isFromMe == message.isFromMe,
                  let candidateText = normalizedAuthorField(candidate.text),
                  normalizedDuplicateDocumentName(candidateText) == normalizedCurrentName,
                  currentText != candidateText,
                  hasDuplicateDocumentCopySuffix(currentText) || hasDuplicateDocumentCopySuffix(candidateText),
                  let messageInfo = state.context.messageInfoByMessageId[candidate.id],
                  let receiptInfo = messageInfo.receiptInfo,
                  let reactions = parseReactions(from: receiptInfo, state: state) else {
                continue
            }

            return reactions
        }

        return nil
    }

    func resolveReactionAuthor(for senderJid: String, state: ChatExportState) -> MessageAuthor? {
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

        return makeParticipantAuthor(
            jid: normalizedJid,
            contactNameGroupMember: nil,
            fallbackSource: .messageJid,
            state: state
        )
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
            let linkedPhoneJid = linkedPhoneJid(for: jid) ?? lidAccountIndex?.phoneJid(for: jid)
            let linkedPhoneDisplayName = try linkedPhoneJid.flatMap {
                try resolvedContactDisplayName(
                    for: $0,
                    profileDisplayName: try ProfilePushName.pushName(for: $0, from: db)
                        .flatMap(normalizedAuthorField),
                    senderPhone: normalizedAuthorField($0.extractedPhone),
                    from: db
                )
            }
            return (
                linkedPhoneDisplayName ?? profileDisplayName,
                normalizedAuthorField(lidAccount.normalizedPhoneNumber) ?? senderPhone
            )
        } else if let linkedPhoneJid = linkedPhoneJid(for: jid) {
            let linkedPhoneDisplayName = try resolvedContactDisplayName(
                for: linkedPhoneJid,
                profileDisplayName: try ProfilePushName.pushName(for: linkedPhoneJid, from: db)
                    .flatMap(normalizedAuthorField),
                senderPhone: normalizedAuthorField(linkedPhoneJid.extractedPhone),
                from: db
            )
            return (linkedPhoneDisplayName, normalizedAuthorField(linkedPhoneJid.extractedPhone))
        } else if let pushName = try ProfilePushName.pushName(for: jid, from: db) {
            return (normalizedAuthorField(pushName), senderPhone)
        } else if let chatSessionName {
            return (chatSessionName, senderPhone)
        } else {
            return (contactNameGroupMember, senderPhone)
        }
    }

    func resolvedContactDisplayName(
        for jid: String,
        profileDisplayName: String?,
        senderPhone: String?,
        from db: Database
    ) throws -> String? {
        if let senderName = try ChatSession.fetchChatSessionName(for: jid, from: db)
            .flatMap(normalizedAuthorField),
           !isPhoneLikeDisplayLabel(senderName, resolvedPhone: senderPhone) {
            return senderName
        }

        if let displayName = addressBookIndex?.contact(for: jid)?.bestDisplayName
            .flatMap(normalizedAuthorField) {
            return displayName
        }

        return profileDisplayName
    }

    func makeParticipantAuthor(
        jid: String,
        contactNameGroupMember: String?,
        fallbackSource: MessageAuthor.Source,
        state: ChatExportState
    ) -> MessageAuthor {
        let cacheKey = ParticipantAuthorCacheKey(
            jid: jid,
            contactName: contactNameGroupMember,
            fallbackSource: fallbackSource.rawValue
        )
        if let cachedAuthor = state.authorsByKey[cacheKey] {
            return cachedAuthor
        }

        let normalizedJid = normalizedAuthorField(jid)
        let phone = resolvedPhone(for: jid)
        let linkedPhoneJid = linkedPhoneJid(for: jid) ?? lidAccountIndex?.phoneJid(for: jid)
        let chatSessionDisplayName = state.context.chatSessionNamesByJid[jid]
            .flatMap(normalizedAuthorField)
        let profileDisplayName = pushNamePhoneJidIndex?.pushName(for: jid)
            .flatMap(whatsAppProfileDisplayName)
        let linkedPhoneDisplayName = linkedPhoneJid
            .flatMap { pushNamePhoneJidIndex?.pushName(for: $0) }
            .flatMap(whatsAppProfileDisplayName)

        let author: MessageAuthor
        if let senderName = chatSessionDisplayName,
           !isPhoneLikeDisplayLabel(senderName, resolvedPhone: phone) {
            author = MessageAuthor(
                kind: .participant,
                displayName: senderName,
                phone: phone,
                jid: normalizedJid,
                source: .chatSession
            )
        } else if let addressBookAuthor = makeAddressBookAuthor(for: jid) {
            author = addressBookAuthor
        } else if let lidAccountAuthor = makeLidAccountAuthor(
            for: jid,
            profileDisplayName: profileDisplayName ?? linkedPhoneDisplayName
        ) {
            author = lidAccountAuthor
        } else if let linkedPhoneJid {
            author = MessageAuthor(
                kind: .participant,
                displayName: profileDisplayName ?? linkedPhoneDisplayName,
                phone: normalizedAuthorField(linkedPhoneJid.extractedPhone),
                jid: normalizedAuthorField(linkedPhoneJid),
                source: .pushNamePhoneJid
            )
        } else if let pushName = profileDisplayName {
            author = MessageAuthor(
                kind: .participant,
                displayName: pushName,
                phone: phone,
                jid: normalizedJid,
                source: .pushName
            )
        } else if let chatSessionDisplayName {
            author = MessageAuthor(
                kind: .participant,
                displayName: chatSessionDisplayName,
                phone: phone,
                jid: normalizedJid,
                source: .chatSession
            )
        } else {
            author = MessageAuthor(
                kind: .participant,
                displayName: normalizedAuthorField(contactNameGroupMember),
                phone: phone,
                jid: normalizedJid,
                source: fallbackSource
            )
        }

        state.authorsByKey[cacheKey] = author
        return author
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
