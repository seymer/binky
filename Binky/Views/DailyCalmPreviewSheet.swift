import SwiftUI
import AppKit

/// **Read-only** Daily Calm preview. Scans a folder, runs the v2
/// `SuggestionEngine`, and renders the resulting `[Suggestion]` as cards —
/// nothing is moved on disk, nothing is persisted to history.
///
/// This is the first UI-visible touchpoint for the Calm Inbox redesign.
/// It is intentionally hidden behind a debug flag (`v2.dailyCalmPreviewEnabled`)
/// so the production app surface is unchanged for normal users; developers
/// and beta testers flip the flag in `defaults` to evaluate the v2 direction
/// without committing to anything.
///
/// What the user sees:
///   - A folder well at the top (defaults to `~/Downloads`).
///   - A "Run preview" action that scans the folder, runs `SuggestionEngine`,
///     and renders one `SuggestionCard` per proposal.
///   - Apply / Skip / Reject buttons on each card that record the decision
///     in local state but **do not** move files. A footer banner makes the
///     dry-run nature explicit so testers can't mistake it for the real
///     thing.
struct DailyCalmPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sourceURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)

    @State private var suggestions: [SuggestionCardModel] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastScanCount: Int = 0
    @State private var lastAlreadyDecidedCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceWell
            content
            Divider()
            footer
        }
        .padding(22)
        .frame(minWidth: 640, minHeight: 480)
        .task {
            // Auto-run on first appear so testers see suggestions without
            // clicking. They can refresh or change the source folder after.
            await runPreview()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Calm — preview")
                    .font(.title2)
                Text("v2 dry-run · nothing on disk is moved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await runPreview() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(isLoading)

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Close")
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var sourceWell: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                Text(sourceURL.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Choose folder…") {
                chooseFolder()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning \(sourceURL.lastPathComponent)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Couldn't run the preview")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suggestions.isEmpty && lastScanCount == 0 {
            // Pre-first-run state. Different from "ran but found nothing" so
            // testers don't mistake an unstarted preview for a clean folder.
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Click Refresh to run the v2 pipeline")
                    .font(.headline)
                Text("Daily Calm reads files from the folder above and proposes where they'd go.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suggestions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("Folder calm.")
                    .font(.headline)
                Text("Scanned \(lastScanCount) file(s); the engine had no proposals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($suggestions) { $card in
                        SuggestionCard(card: $card)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            Text("Read-only preview — Apply/Skip/Reject persist to ~/Library/Application Support/Binky.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if lastAlreadyDecidedCount > 0 {
                Text("\(lastAlreadyDecidedCount) already decided")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Forget all") {
                    SuggestionStore.shared.clearAll()
                    Task { await runPreview() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if lastScanCount > 0 {
                Text("\(suggestions.count) pending · \(lastScanCount) file(s)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceURL
        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
            Task { await runPreview() }
        }
    }

    @MainActor
    private func runPreview() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let folder = sourceURL
        let inboxRoot = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Binky-v2-preview", isDirectory: true)

        do {
            let result = try await Self.scanAndSuggest(folder: folder, inboxRoot: inboxRoot)
            self.suggestions = result.cards
            self.lastScanCount = result.scannedCount
            self.lastAlreadyDecidedCount = result.alreadyDecidedCount
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Pulled out as a `nonisolated static` so the heavy work runs off the
    /// main actor — keeps the SwiftUI view thread responsive while the engine
    /// hashes potentially-large files. The view-side bookkeeping (suggestions,
    /// error, isLoading) is updated back on the main actor by the caller.
    ///
    /// **Filter rule:** suggestions that already have a persisted decision
    /// in `SuggestionStore` (accepted / rejected / snoozed) are dropped from
    /// the card list. The whole point of recording decisions is so Daily Calm
    /// stops nagging — re-asking about a file the user already rejected
    /// would defeat the trust-first design.
    nonisolated private static func scanAndSuggest(
        folder: URL,
        inboxRoot: URL
    ) async throws -> (cards: [SuggestionCardModel], scannedCount: Int, alreadyDecidedCount: Int) {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let regularFiles = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        let inboxRootResolver: InboxRootResolver = { category in
            inboxRoot.appendingPathComponent(category.downloadsSubfolder, isDirectory: true)
        }
        let engine = SuggestionEngine(
            adapters: [
                HeuristicSuggestionAdapter(inboxRoot: inboxRootResolver),
                FoundationModelsSuggestionAdapter(inboxRoot: inboxRootResolver),
            ]
        )
        let store = SuggestionStore.shared

        var cards: [SuggestionCardModel] = []
        var alreadyDecided = 0
        for url in regularFiles {
            // Adapter errors are absorbed inside the engine; only ingestion
            // throws here. Skip individual failures so one bad file doesn't
            // wipe the whole preview list.
            guard let suggestions = try? await engine.suggest(for: url) else { continue }
            for s in suggestions {
                if store.decision(for: s) != nil {
                    alreadyDecided += 1
                    continue
                }
                cards.append(SuggestionCardModel(suggestion: s))
            }
        }
        return (cards, regularFiles.count, alreadyDecided)
    }
}

// MARK: - Card model + view

/// Local UI state for a single Daily Calm card. We deliberately don't
/// mutate the `Suggestion` itself — the engine treats `Suggestion` as
/// immutable per call, so per-render state lives here instead.
struct SuggestionCardModel: Identifiable {
    let id: UUID
    let suggestion: Suggestion
    var localDecision: LocalDecision = .pending

    enum LocalDecision: Equatable {
        case pending
        case applied
        case skipped
        case rejected
    }

    init(suggestion: Suggestion) {
        self.id = suggestion.id
        self.suggestion = suggestion
    }
}

private struct SuggestionCard: View {
    @Binding var card: SuggestionCardModel

    private var s: Suggestion { card.suggestion }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: actionIcon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(s.source.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let confidence = s.confidence {
                    Text(String(format: "%.0f%%", confidence * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(actionDescription)
                .font(.subheadline)

            Text(s.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Group {
                    decisionButton(label: "Apply", target: .applied, role: nil, prominent: true)
                    decisionButton(label: "Skip", target: .skipped, role: .cancel, prominent: false)
                    decisionButton(label: "Reject", target: .rejected, role: .destructive, prominent: false)
                }
                .disabled(card.localDecision != .pending)

                Spacer()

                if card.localDecision != .pending {
                    Text(decisionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(decisionColor)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionIcon: String {
        switch s.action {
        case .move: return "folder.fill"
        case .rename: return "pencil"
        case .trash: return "trash"
        case .keep: return "lock.fill"
        case .runShortcut: return "bolt.fill"
        }
    }

    private var actionDescription: String {
        switch s.action {
        case .move(let dest):
            return "Move → \(humanReadablePath(dest))"
        case .rename(let name):
            return "Rename → \(name)"
        case .trash:
            return "Move to Trash"
        case .keep:
            return "Keep where it is"
        case .runShortcut(let name):
            return "Run Shortcut: \(name)"
        }
    }

    private func humanReadablePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    @ViewBuilder
    private func decisionButton(
        label: String,
        target: SuggestionCardModel.LocalDecision,
        role: ButtonRole?,
        prominent: Bool
    ) -> some View {
        if prominent {
            Button(role: role) { applyDecision(target) } label: { Text(label) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(role: role) { applyDecision(target) } label: { Text(label) }
                .buttonStyle(.bordered)
        }
    }

    /// Updates the card's in-window state AND persists the corresponding
    /// `UserDecision` to `SuggestionStore`. Persistence means the next
    /// `runPreview` will filter this suggestion out — Daily Calm doesn't
    /// nag about decisions you already made.
    ///
    /// `LocalDecision → UserDecision` mapping:
    ///   - applied  → .accepted (user OK'd this proposal)
    ///   - skipped  → .snoozed  (not now, ask again later)
    ///   - rejected → .rejected (don't ask again about this proposal)
    ///   - pending  → no persistence (shouldn't happen via this button)
    private func applyDecision(_ target: SuggestionCardModel.LocalDecision) {
        card.localDecision = target
        let user: UserDecision?
        switch target {
        case .pending:  user = nil
        case .applied:  user = .accepted
        case .skipped:  user = .snoozed
        case .rejected: user = .rejected
        }
        if let user {
            SuggestionStore.shared.record(card.suggestion, decision: user)
        }
    }

    private var decisionLabel: String {
        switch card.localDecision {
        case .pending: return ""
        case .applied: return "✓ Applied (preview only)"
        case .skipped: return "Skipped"
        case .rejected: return "Rejected"
        }
    }

    private var decisionColor: Color {
        switch card.localDecision {
        case .pending: return .secondary
        case .applied: return .green
        case .skipped: return .secondary
        case .rejected: return .red
        }
    }
}
