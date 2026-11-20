import SwiftUI

struct ConversationListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let selectionBinding = Binding<ConversationInfo?>(
            get: { appState.selectedConversation },
            set: { appState.selectedConversation = $0 }
        )
        let searchBinding = Binding<String>(
            get: { appState.searchText },
            set: { appState.searchText = $0 }
        )

        ZStack(alignment: .bottom) {
            List(appState.filteredConversations, selection: selectionBinding) { conversation in
                ConversationRowView(conversation: conversation)
                    .tag(conversation)
            }
            .disabled(appState.isExportingPDF)
            .searchable(text: searchBinding, prompt: "Search conversations")
            .navigationTitle("Conversations")
            .onChange(of: appState.selectedConversation) { _, newValue in
                if let conversation = newValue {
                    appState.loadMessages(for: conversation)
                }
            }

            // Progress pill while streaming
            if appState.isLoadingConversations {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(appState.loadedConversationCount) / \(appState.totalConversationCount)")
                        .font(.callout)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if appState.conversations.isEmpty && !appState.isLoadingConversations {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "message",
                    description: Text("No message conversations found.")
                )
            } else if !appState.conversations.isEmpty && appState.filteredConversations.isEmpty {
                ContentUnavailableView.search(text: appState.searchText)
            }
        }
    }
}
