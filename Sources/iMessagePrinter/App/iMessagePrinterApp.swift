import SwiftUI
import Foundation
import AppKit

enum HeadlessCLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--headless-export"), idx + 2 < args.count else {
            return false
        }
        let target = args[idx + 1]
        let outPath = args[idx + 2]
        let modeStr = (idx + 3 < args.count) ? args[idx + 3].lowercased() : "thumbnail"
        let mode: PDFExportService.AttachmentMode
        switch modeStr {
        case "omit", "none": mode = .omit
        case "full", "fullresolution": mode = .fullResolution
        default: mode = .thumbnail
        }

        do {
            let db = try DatabaseService()
            let handleMap = try db.fetchAllHandles()
            let resolver = ContactResolver()
            let raws = try db.fetchConversations()
            let needle = target.lowercased()
            let needleDigits = target.filter(\.isNumber)

            var matchedRaw: RawConversation?
            for raw in raws {
                let handles = try db.fetchHandlesForChat(chatRowID: raw.rowID)
                let hay = ([raw.chatIdentifier ?? "", raw.displayName ?? ""] + handles.map(\.id)).joined(separator: " ").lowercased()
                let hayDigits = hay.filter(\.isNumber)
                if String(raw.rowID) == target || hay.contains(needle) || (!needleDigits.isEmpty && needleDigits.count >= 7 && hayDigits.contains(needleDigits)) {
                    matchedRaw = raw
                    break
                }
            }

            guard let chosen = matchedRaw else {
                FileHandle.standardError.write(Data("No conversation matched target: \(target)\n".utf8))
                exit(2)
            }

            let chatHandles = try db.fetchHandlesForChat(chatRowID: chosen.rowID)
            let participants = chatHandles.map(\.id)
            let participantNames = chatHandles.map { resolver.displayName(for: $0.id) }
            let displayName = (chosen.displayName?.isEmpty == false)
                ? chosen.displayName!
                : (participantNames.isEmpty ? (chosen.chatIdentifier ?? target) : participantNames.joined(separator: ", "))

            let convInfo = ConversationInfo(
                chatRowID: chosen.rowID,
                chatGUID: chosen.guid,
                displayName: displayName,
                participants: participants,
                participantNames: participantNames,
                messageCount: chosen.messageCount,
                lastMessageDate: DateFormatting.dateFromAppleTimestamp(chosen.lastMessageDate),
                lastMessagePreview: nil,
                isGroupChat: chosen.style == 43,
                serviceName: chosen.serviceName ?? "iMessage"
            )

            let records = try db.fetchMessages(chatRowID: chosen.rowID)
            let reactionMap = ReactionAggregator.aggregate(messages: records, handleMap: handleMap, contactResolver: resolver)
            var displayMessages: [DisplayMessage] = []

            for record in records {
                if record.isReaction || record.isReactionRemoval { continue }
                var text = record.text
                if (text == nil || text?.isEmpty == true), let blob = record.attributedBody {
                    text = AttributedBodyParser.extractText(from: blob)
                }
                let senderID: String
                let senderName: String
                if record.isFromMe {
                    senderID = "Me"
                    senderName = "Me"
                } else if let h = handleMap[record.handleID] {
                    senderID = h.id
                    senderName = resolver.displayName(for: h.id)
                } else {
                    senderID = "Unknown"
                    senderName = "Unknown"
                }

                var atts: [DisplayAttachment] = []
                if record.cacheHasAttachments {
                    for a in try db.fetchAttachments(messageRowID: record.rowID) {
                        atts.append(DisplayAttachment(
                            id: a.rowID,
                            filename: a.filename,
                            transferName: a.transferName,
                            mimeType: a.mimeType,
                            totalBytes: a.totalBytes,
                            isImage: a.isImage,
                            resolvedPath: a.resolvedPath,
                            formattedSize: a.formattedSize,
                            image: nil
                        ))
                    }
                }

                displayMessages.append(DisplayMessage(
                    id: record.rowID,
                    guid: record.guid,
                    text: text,
                    senderName: senderName,
                    senderID: senderID,
                    isFromMe: record.isFromMe,
                    date: DateFormatting.dateFromAppleTimestamp(record.date),
                    dateRead: DateFormatting.dateFromAppleTimestamp(record.dateRead),
                    dateDelivered: DateFormatting.dateFromAppleTimestamp(record.dateDelivered),
                    service: record.service ?? "iMessage",
                    isDelivered: record.isDelivered,
                    isRead: record.isRead,
                    isSent: record.isSent,
                    isSystemMessage: record.isSystemMessage,
                    isEdited: (record.dateEdited ?? 0) > 0,
                    isRetracted: (record.dateRetracted ?? 0) > 0,
                    replyToGUID: record.replyToGUID,
                    threadOriginatorGUID: record.threadOriginatorGUID,
                    groupTitle: record.groupTitle,
                    groupActionType: record.groupActionType,
                    reactions: reactionMap[record] ?? [],
                    attachments: atts
                ))
            }

            let outURL = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PDFExportService.export(conversation: convInfo, messages: displayMessages, attachmentMode: mode, to: outURL)
            print("{\"status\":\"exported\",\"chatRowID\":\(chosen.rowID),\"messages\":\(displayMessages.count),\"pdf\":\"\(outURL.path)\"}")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Headless export error: \(error)\n".utf8))
            exit(1)
        }
    }
}

@main
struct iMessagePrinterApp: App {
    private var appState: AppState

    init() {
        _ = HeadlessCLI.runIfRequested()
        self.appState = AppState()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
