import Foundation
import SwiftWABackupAPI

enum CLIError: LocalizedError {
    case invalidArguments(String)
    case iPhoneBackupNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .iPhoneBackupNotFound(let identifier):
            return "iPhone backup '\(identifier)' not found."
        }
    }
}

enum HelpTopic {
    case root
    case listIPhoneBackups
    case listChats
    case exportChat
    case extractWhatsAppBackup
}

enum CLICommand {
    case help(HelpTopic)
    case listIPhoneBackups(iPhoneBackupsPath: String, json: Bool, pretty: Bool)
    case listChats(
        whatsAppBackupPath: String,
        photosDirectory: String?,
        json: Bool,
        pretty: Bool
    )
    case exportChat(
        whatsAppBackupPath: String,
        chatId: Int,
        outputJSON: String?,
        outputDirectory: String?,
        pretty: Bool
    )
    case extractWhatsAppBackup(
        iPhoneBackupsPath: String,
        iPhoneBackupId: String?,
        outputDirectory: String,
        overwriteExisting: Bool
    )
}

struct CLICommandParser {
    let arguments: [String]

    func parse() throws -> CLICommand {
        guard let first = arguments.first else {
            return .help(.root)
        }

        if first == "--help" || first == "-h" || first == "help" {
            return .help(.root)
        }

        switch first {
        case "list-iphone-backups":
            if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") {
                return .help(.listIPhoneBackups)
            }

            var iPhoneBackupsPath = "~/Library/Application Support/MobileSync/Backup/"
            var json = false
            var pretty = false

            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--iphone-backups-path":
                    iPhoneBackupsPath = try requireValue(for: argument, at: index)
                    index += 2
                case "--json":
                    json = true
                    index += 1
                case "--pretty":
                    pretty = true
                    index += 1
                default:
                    throw CLIError.invalidArguments("Unknown argument '\(argument)'.")
                }
            }

            return .listIPhoneBackups(iPhoneBackupsPath: iPhoneBackupsPath, json: json, pretty: pretty)

        case "list-chats":
            if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") {
                return .help(.listChats)
            }

            var whatsAppBackupPath: String?
            var photosDirectory: String?
            var json = false
            var pretty = false

            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--whatsapp-backup-path":
                    whatsAppBackupPath = try requireValue(for: argument, at: index)
                    index += 2
                case "--photos-dir":
                    photosDirectory = try requireValue(for: argument, at: index)
                    index += 2
                case "--json":
                    json = true
                    index += 1
                case "--pretty":
                    pretty = true
                    index += 1
                default:
                    throw CLIError.invalidArguments("Unknown argument '\(argument)'.")
                }
            }

            guard let whatsAppBackupPath else {
                throw CLIError.invalidArguments("Missing required argument --whatsapp-backup-path.")
            }

            return .listChats(
                whatsAppBackupPath: whatsAppBackupPath,
                photosDirectory: photosDirectory,
                json: json,
                pretty: pretty
            )

        case "export-chat":
            if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") {
                return .help(.exportChat)
            }

            var whatsAppBackupPath: String?
            var chatId: Int?
            var outputJSON: String?
            var outputDirectory: String?
            var pretty = false

            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--whatsapp-backup-path":
                    whatsAppBackupPath = try requireValue(for: argument, at: index)
                    index += 2
                case "--chat-id":
                    let rawValue = try requireValue(for: argument, at: index)
                    guard let parsed = Int(rawValue) else {
                        throw CLIError.invalidArguments("Invalid value '\(rawValue)' for --chat-id.")
                    }
                    chatId = parsed
                    index += 2
                case "--output-json":
                    outputJSON = try requireValue(for: argument, at: index)
                    index += 2
                case "--output-dir":
                    outputDirectory = try requireValue(for: argument, at: index)
                    index += 2
                case "--output":
                    throw CLIError.invalidArguments("Use --output-json for a JSON file or --output-dir for a full chat export directory.")
                case "--media-dir":
                    throw CLIError.invalidArguments("Use --output-dir to export the JSON and media for a chat into one directory.")
                case "--json":
                    throw CLIError.invalidArguments("export-chat already emits JSON. Use --pretty to format it or --output-json to write it to disk.")
                case "--pretty":
                    pretty = true
                    index += 1
                default:
                    throw CLIError.invalidArguments("Unknown argument '\(argument)'.")
                }
            }

            guard let chatId else {
                throw CLIError.invalidArguments("Missing required argument --chat-id.")
            }

            if outputJSON != nil && outputDirectory != nil {
                throw CLIError.invalidArguments("Use either --output-json or --output-dir, but not both.")
            }

            guard let whatsAppBackupPath else {
                throw CLIError.invalidArguments("Missing required argument --whatsapp-backup-path.")
            }

            return .exportChat(
                whatsAppBackupPath: whatsAppBackupPath,
                chatId: chatId,
                outputJSON: outputJSON,
                outputDirectory: outputDirectory,
                pretty: pretty
            )

        case "extract-whatsapp-backup":
            if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") {
                return .help(.extractWhatsAppBackup)
            }

            var iPhoneBackupsPath = "~/Library/Application Support/MobileSync/Backup/"
            var iPhoneBackupId: String?
            var outputDirectory: String?
            var overwriteExisting = false

            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--iphone-backups-path":
                    iPhoneBackupsPath = try requireValue(for: argument, at: index)
                    index += 2
                case "--iphone-backup-id":
                    iPhoneBackupId = try requireValue(for: argument, at: index)
                    index += 2
                case "--output-dir":
                    outputDirectory = try requireValue(for: argument, at: index)
                    index += 2
                case "--overwrite":
                    overwriteExisting = true
                    index += 1
                default:
                    throw CLIError.invalidArguments("Unknown argument '\(argument)'.")
                }
            }

            guard let outputDirectory else {
                throw CLIError.invalidArguments("Missing required argument --output-dir.")
            }

            return .extractWhatsAppBackup(
                iPhoneBackupsPath: iPhoneBackupsPath,
                iPhoneBackupId: iPhoneBackupId,
                outputDirectory: outputDirectory,
                overwriteExisting: overwriteExisting
            )

        default:
            throw CLIError.invalidArguments("Unknown command '\(first)'.")
        }
    }

    private func requireValue(for argument: String, at index: Int) throws -> String {
        let nextIndex = index + 1
        guard arguments.indices.contains(nextIndex) else {
            throw CLIError.invalidArguments("Missing value for \(argument).")
        }
        return arguments[nextIndex]
    }
}

struct CLIApplication {
    typealias OutputWriter = (String) -> Void
    private let iso8601Formatter = ISO8601DateFormatter()

    func run(
        arguments: [String],
        standardOutput: OutputWriter = { print($0) },
        standardError: OutputWriter = { fputs($0 + "\n", stderr) }
    ) -> Int32 {
        do {
            let command = try CLICommandParser(arguments: arguments).parse()

            switch command {
            case .help(let topic):
                standardOutput(Self.usage(for: topic))
                return 0
            case .listIPhoneBackups(let iPhoneBackupsPath, let json, let pretty):
                try handleListIPhoneBackups(
                    iPhoneBackupsPath: iPhoneBackupsPath,
                    json: json,
                    pretty: pretty,
                    standardOutput: standardOutput
                )
            case .listChats(let whatsAppBackupPath, let photosDirectory, let json, let pretty):
                try handleListChats(
                    whatsAppBackupPath: whatsAppBackupPath,
                    photosDirectory: photosDirectory,
                    json: json,
                    pretty: pretty,
                    standardOutput: standardOutput
                )
            case .exportChat(
                let whatsAppBackupPath,
                let chatId,
                let outputJSON,
                let outputDirectory,
                let pretty
            ):
                try handleExportChat(
                    whatsAppBackupPath: whatsAppBackupPath,
                    chatId: chatId,
                    outputJSON: outputJSON,
                    outputDirectory: outputDirectory,
                    pretty: pretty,
                    standardOutput: standardOutput
                )
            case .extractWhatsAppBackup(
                let iPhoneBackupsPath,
                let iPhoneBackupId,
                let outputDirectory,
                let overwriteExisting
            ):
                try handleExtractWhatsAppBackup(
                    iPhoneBackupsPath: iPhoneBackupsPath,
                    iPhoneBackupId: iPhoneBackupId,
                    outputDirectory: outputDirectory,
                    overwriteExisting: overwriteExisting,
                    standardOutput: standardOutput
                )
            }

            return 0
        } catch let error as LocalizedError {
            standardError(error.errorDescription ?? String(describing: error))
            return 1
        } catch {
            standardError(String(describing: error))
            return 1
        }
    }

    private func handleListIPhoneBackups(
        iPhoneBackupsPath: String,
        json: Bool,
        pretty: Bool,
        standardOutput: OutputWriter
    ) throws {
        let waBackup = WABackup(iPhoneBackupsPath: iPhoneBackupsPath)
        let inspections = try waBackup.inspectIPhoneBackups()

        if json {
            let payload = IPhoneBackupListPayload(
                iPhoneBackups: inspections.map(IPhoneBackupListPayload.IPhoneBackupInspection.init)
            )
            standardOutput(try renderJSON(payload, pretty: pretty))
            return
        }

        if inspections.isEmpty {
            standardOutput("No iPhone backups found.")
            return
        }

        for inspection in inspections {
            standardOutput(renderIPhoneBackupInspectionLine(inspection))
        }
    }

    private func handleListChats(
        whatsAppBackupPath: String,
        photosDirectory: String?,
        json: Bool,
        pretty: Bool,
        standardOutput: OutputWriter
    ) throws {
        let source = try openWhatsAppBackup(at: whatsAppBackupPath)
        let photosURL = try photosDirectory.map(createDirectoryIfNeeded(at:))
        let chats = try source.waBackup.getChats(directoryToSavePhotos: photosURL)

        if json {
            standardOutput(try renderJSON(chats, pretty: pretty))
            return
        }

        standardOutput(source.headerLine)
        for chat in chats {
            standardOutput(
                "\(chat.id)\t\(chat.chatType.rawValue)\t\(chat.numberMessages)\t"
                    + "\(iso8601Formatter.string(from: chat.lastMessageDate))\t\(chat.name)"
            )
        }
    }

    private func handleExportChat(
        whatsAppBackupPath: String,
        chatId: Int,
        outputJSON: String?,
        outputDirectory: String?,
        pretty: Bool,
        standardOutput: OutputWriter
    ) throws {
        let source = try openWhatsAppBackup(at: whatsAppBackupPath)
        let exportDirectoryURL = try outputDirectory.map(createDirectoryIfNeeded(at:))
        let jsonOutputURL = try outputJSON.map { try resolveOutputJSONURL(at: $0) }
        let mediaURL = exportDirectoryURL
        let payload = try source.waBackup.getChat(chatId: chatId, directoryToSaveMedia: mediaURL)
        let rendered = try renderJSON(payload, pretty: pretty)

        if let exportDirectoryURL {
            let outputURL = exportDirectoryURL.appendingPathComponent("chat-\(chatId).json")
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rendered.write(to: outputURL, atomically: true, encoding: .utf8)
            standardOutput("Wrote chat \(chatId) from \(source.outputDescription) to \(outputURL.path)")
        } else if let jsonOutputURL {
            try FileManager.default.createDirectory(
                at: jsonOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rendered.write(to: jsonOutputURL, atomically: true, encoding: .utf8)
            standardOutput("Wrote chat \(chatId) from \(source.outputDescription) to \(jsonOutputURL.path)")
        } else {
            standardOutput(rendered)
        }
    }

    private func handleExtractWhatsAppBackup(
        iPhoneBackupsPath: String,
        iPhoneBackupId: String?,
        outputDirectory: String,
        overwriteExisting: Bool,
        standardOutput: OutputWriter
    ) throws {
        let backup = try resolveReadyIPhoneBackup(
            iPhoneBackupsPath: iPhoneBackupsPath,
            iPhoneBackupId: iPhoneBackupId
        )
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        let extractedBackup = try backup.extractWhatsAppBackup(
            to: outputURL,
            overwriteExisting: overwriteExisting
        )

        standardOutput("Extracted WhatsApp backup \(backup.identifier) to \(extractedBackup.path)")
    }

    private func openWhatsAppBackup(at whatsAppBackupPath: String) throws -> OpenedWhatsAppBackup {
        let backupURL = URL(fileURLWithPath: whatsAppBackupPath, isDirectory: true)
        let waBackup = try WABackup(whatsAppBackupAt: backupURL)

        return OpenedWhatsAppBackup(
            waBackup: waBackup,
            headerLine: "WhatsApp backup: \(backupURL.path)",
            outputDescription: "WhatsApp backup \(backupURL.path)"
        )
    }

    private func resolveReadyIPhoneBackup(
        iPhoneBackupsPath: String,
        iPhoneBackupId: String?
    ) throws -> IPhoneBackup {
        let waBackup = WABackup(iPhoneBackupsPath: iPhoneBackupsPath)
        let inspections = try waBackup.inspectIPhoneBackups()
        let inspection: IPhoneBackupDiscoveryInfo

        if let iPhoneBackupId {
            guard let matched = inspections.first(where: { $0.identifier == iPhoneBackupId }) else {
                throw CLIError.iPhoneBackupNotFound(iPhoneBackupId)
            }
            inspection = matched
        } else {
            guard let first = inspections.first(where: \.isReady) else {
                throw CLIError.invalidArguments(
                    "No ready iPhone backups found. Run 'list-iphone-backups' to inspect encryption status and backup diagnostics."
                )
            }
            inspection = first
        }

        guard inspection.isReady, let backup = inspection.iPhoneBackup else {
            let issue = inspection.issue ?? "iPhone backup status is \(inspection.status.rawValue)."
            throw CLIError.invalidArguments(
                "iPhone backup '\(inspection.identifier)' is not ready for WhatsApp extraction: \(issue)"
            )
        }

        return backup
    }

    private func renderIPhoneBackupInspectionLine(_ inspection: IPhoneBackupDiscoveryInfo) -> String {
        let creationDate = inspection.creationDate.map(iso8601Formatter.string(from:)) ?? "-"
        let encryptionState: String
        if let isEncrypted = inspection.isEncrypted {
            encryptionState = isEncrypted ? "ENCRYPTED" : "NOT_ENCRYPTED"
        } else {
            encryptionState = "UNKNOWN"
        }

        var columns = [
            iPhoneBackupStatusLabel(for: inspection.status),
            inspection.identifier,
            creationDate,
            encryptionState,
            inspection.path
        ]

        if let issue = inspection.issue {
            columns.append(issue)
        }

        return columns.joined(separator: "\t")
    }

    private func iPhoneBackupStatusLabel(for status: IPhoneBackupDiscoveryStatus) -> String {
        switch status {
        case .ready:
            return "READY"
        case .encrypted:
            return "ENCRYPTED"
        case .encryptionStatusUnavailable:
            return "UNKNOWN_ENCRYPTION"
        case .missingRequiredFile:
            return "INVALID_MISSING_FILE"
        case .malformedStatusPlist:
            return "INVALID_STATUS_PLIST"
        case .missingWhatsAppDatabase:
            return "NO_WHATSAPP_DATABASE"
        case .unreadableManifestDatabase:
            return "UNREADABLE_MANIFEST_DB"
        case .unreadableBackup:
            return "UNREADABLE_BACKUP"
        }
    }

    private func resolveOutputJSONURL(at path: String) throws -> URL {
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CLIError.invalidArguments("--output-json expects a file path, but '\(path)' is a directory.")
        }

        return URL(fileURLWithPath: path)
    }

    private func createDirectoryIfNeeded(at path: String) throws -> URL {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func renderJSON<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }

        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidArguments("Unable to encode JSON as UTF-8.")
        }
        return string
    }

    static func usage(for topic: HelpTopic) -> String {
        switch topic {
        case .root:
            return """
            Usage: SwiftWABackupCLI <command> [options]

            Commands:
              list-iphone-backups
                  Discover iPhone backups under a root folder.
              list-chats
                  List chats from an extracted WhatsApp backup.
              export-chat
                  Export a chat from an extracted WhatsApp backup.
              extract-whatsapp-backup
                  Copy WhatsApp files out of an iPhone backup.

            Run 'SwiftWABackupCLI <command> --help' for command-specific options.
            """
        case .listIPhoneBackups:
            return """
            Usage: SwiftWABackupCLI list-iphone-backups [options]

            Options:
              --iphone-backups-path <path>   Root directory that contains iPhone backups.
              --json                         Emit JSON instead of text output.
              --pretty                       Pretty-print JSON output.
            """
        case .listChats:
            return """
            Usage: SwiftWABackupCLI list-chats [options]

            Options:
              --whatsapp-backup-path <path>
                                      Extracted WhatsApp backup directory.
              --photos-dir <path>    Optional directory where chat photos will be copied.
              --json                 Emit JSON instead of text output.
              --pretty               Pretty-print JSON output.
            """
        case .exportChat:
            return """
            Usage: SwiftWABackupCLI export-chat [options]

            Options:
              --whatsapp-backup-path <path>
                                      Extracted WhatsApp backup directory.
              --chat-id <id>         Chat identifier to export.
              --output-json <path>   Optional JSON file path. Exports only the JSON payload.
              --output-dir <path>    Optional export directory. Writes chat-<id>.json and copies media there.
              --pretty               Pretty-print JSON output.
            """
        case .extractWhatsAppBackup:
            return """
            Usage: SwiftWABackupCLI extract-whatsapp-backup [options]

            Options:
              --iphone-backups-path <path>   Root directory that contains iPhone backups.
              --iphone-backup-id <id>        iPhone backup identifier. Defaults to the first ready backup.
              --output-dir <path>            Directory where the WhatsApp tree will be reconstructed.
              --overwrite                    Replace existing files in the output directory.
            """
        }
    }
}

private struct OpenedWhatsAppBackup {
    let waBackup: WABackup
    let headerLine: String
    let outputDescription: String
}

private struct IPhoneBackupListPayload: Encodable {
    struct IPhoneBackupInspection: Encodable {
        let identifier: String
        let path: String
        let creationDate: Date?
        let isEncrypted: Bool?
        let isReady: Bool
        let status: IPhoneBackupDiscoveryStatus
        let issue: String?

        init(_ inspection: IPhoneBackupDiscoveryInfo) {
            identifier = inspection.identifier
            path = inspection.path
            creationDate = inspection.creationDate
            isEncrypted = inspection.isEncrypted
            isReady = inspection.isReady
            status = inspection.status
            issue = inspection.issue
        }
    }

    let iPhoneBackups: [IPhoneBackupInspection]
}
