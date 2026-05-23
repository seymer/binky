import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main View

/// Binky 2.0 main window. Replaces the v1 OrganizerMainView entirely.
///
/// Flow: Select sources → Configure destinations → Scan → Review suggestions → Apply.
struct DailyCalmPreviewSheet: View {
    @EnvironmentObject var prefs: BinkyPreferences

    // MARK: State

    @State private var sources: [URL] = []
    @State private var includeSubfolders: Bool = true

    @State private var suggestions: [SuggestionCardModel] = []
    @State private var duplicates: [DuplicateGroup] = []
    @State private var isScanning: Bool = false
    @State private var lastScanFileCount: Int = 0
    @State private var lastAlreadyDecidedCount: Int = 0
    @State private var errorMessage: String? = nil

    @State private var filterCategory: FileSortCategory? = nil
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HSplitView {
                configPanel
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                resultsPanel
                    .frame(minWidth: 400)
            }
            Divider()
            footerBar
        }
        .frame(minWidth: 720, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay(dropOverlay)
        .task { initializeFromPrefs() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Binky")
                .font(.title2.bold())
            Spacer()
            Button {
                Task { await scan() }
            } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(sources.isEmpty || isScanning)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Config Panel (left)

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourcesSection
            }
            .padding(16)
        }
        .background(Color.primary.opacity(0.02))
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sources", systemImage: "folder.badge.plus")
                .font(.headline)

            ForEach(sources, id: \.self) { url in
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                    Text(shortenPath(url.path))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { sources.removeAll { $0 == url } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            if sources.isEmpty {
                Text("Drop folders here or click + to add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("+ Add folder") { addSource() }
                    .buttonStyle(.borderless)
                Button("+ Add files") { addFiles() }
                    .buttonStyle(.borderless)
            }

            Toggle("Include subfolders", isOn: $includeSubfolders)
                .font(.caption)
        }
    }


    // MARK: - Results Panel (right)

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            if isScanning {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Spacer()
            } else if suggestions.isEmpty && duplicates.isEmpty && lastScanFileCount == 0 {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Add sources and hit Scan")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if suggestions.isEmpty && duplicates.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("All clear.")
                        .font(.headline)
                }
                Spacer()
            } else {
                filterBar
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !duplicates.isEmpty {
                            duplicateSection
                        }
                        ForEach(groupedBySource.indices, id: \.self) { idx in
                            let group = groupedBySource[idx]
                            if matchesFilter(group.primary) {
                                SuggestionRow(
                                    card: bindingForCard(group.primary.id),
                                    siblings: group.all
                                )
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Text("Filter:")
                .font(.caption)
                .foregroundStyle(.secondary)
            filterButton("All", isActive: filterCategory == nil) { filterCategory = nil }
            ForEach(activeCategories, id: \.self) { cat in
                filterButton(cat.rawValue.capitalized, isActive: filterCategory == cat) { filterCategory = cat }
            }
            Spacer()
            batchApplyMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private var batchApplyMenu: some View {
        Menu {
            Button("Apply all (\(pendingSuggestions.count))") { batchApply(filter: nil) }
            Divider()
            ForEach(activeCategories, id: \.self) { cat in
                let count = pendingSuggestions.filter { categorize($0) == cat }.count
                if count > 0 {
                    Button("Apply \(cat.rawValue.capitalized) (\(count))") { batchApply(filter: cat) }
                }
            }
        } label: {
            Label("Apply…", systemImage: "checkmark.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .disabled(pendingSuggestions.isEmpty)
    }

    @ViewBuilder
    private var duplicateSection: some View {
        Section {
            ForEach($duplicates) { $group in
                DuplicateCard(group: $group)
            }
        } header: {
            Label("Duplicates found", systemImage: "doc.on.doc.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if lastScanFileCount > 0 {
                Text("\(lastScanFileCount) scanned · \(suggestions.count) suggestions · \(duplicates.count) duplicate groups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if lastAlreadyDecidedCount > 0 {
                    Text("· \(lastAlreadyDecidedCount) already decided")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Reset") {
                        SuggestionStore.shared.clearAll()
                        Task { await scan() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            Spacer()
            Text("Apply moves files for real.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Drop overlay

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .background(Color.accentColor.opacity(0.05))
                .overlay(
                    Label("Drop to add sources", systemImage: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                )
                .padding(8)
        }
    }

    // MARK: - Actions

    private func initializeFromPrefs() {
        let defaultSource = prefs.activeSortSweepRootDirectory()
        if sources.isEmpty {
            sources = [defaultSource]
        }
    }

    private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) {
                sources.append(url)
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) {
                sources.append(url)
            }
            Task { await scan() }
        }
    }


    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if !sources.contains(url) {
                        sources.append(url)
                    }
                }
            }
        }
        // Auto-scan after drop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { await scan() }
        }
    }

    @MainActor
    private func scan() async {
        guard !isScanning, !sources.isEmpty else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        do {
            let result = try await Self.performScan(
                sources: sources,
                includeSubfolders: includeSubfolders,
                    )
            suggestions = result.cards
            duplicates = result.duplicates
            lastScanFileCount = result.fileCount
            lastAlreadyDecidedCount = result.alreadyDecided
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func batchApply(filter: FileSortCategory?) {
        let executor = SuggestionExecutor()
        for i in suggestions.indices {
            guard suggestions[i].localDecision == .pending else { continue }
            if let filter, categorize(suggestions[i]) != filter { continue }
            let result = executor.execute(suggestions[i].suggestion)
            if result.succeeded {
                suggestions[i].localDecision = .applied
                suggestions[i].executionResult = {
                    if case .success(let p) = result.outcome { return p }
                    return nil
                }()
                SuggestionStore.shared.record(suggestions[i].suggestion, decision: .accepted)
            }
        }
    }

    // MARK: - Helpers

    private var pendingSuggestions: [SuggestionCardModel] {
        suggestions.filter { $0.localDecision == .pending }
    }

    /// Groups suggestions by source URL. Each group's `primary` is the first
    /// card (used for rendering the row); `all` contains every suggestion for
    /// that source (the candidate destinations the user picks from).
    private var groupedBySource: [(primary: SuggestionCardModel, all: [Suggestion])] {
        var seen: [String: Int] = [:]
        var groups: [(primary: SuggestionCardModel, all: [Suggestion])] = []
        for card in suggestions {
            let key = card.suggestion.source.standardizedFileURL.path
            if let idx = seen[key] {
                groups[idx].all.append(card.suggestion)
            } else {
                seen[key] = groups.count
                groups.append((primary: card, all: [card.suggestion]))
            }
        }
        return groups
    }

    private func bindingForCard(_ id: UUID) -> Binding<SuggestionCardModel> {
        Binding(
            get: { suggestions.first { $0.id == id } ?? suggestions[0] },
            set: { new in
                if let idx = suggestions.firstIndex(where: { $0.id == id }) {
                    suggestions[idx] = new
                }
            }
        )
    }

    private var activeCategories: [FileSortCategory] {
        let cats = Set(suggestions.map { categorize($0) })
        return FileSortCategory.allCases.filter { cats.contains($0) }
    }

    private func categorize(_ card: SuggestionCardModel) -> FileSortCategory {
        // Derive category from the suggestion's destination path
        if case .move(let dest) = card.suggestion.action {
            let last = dest.lastPathComponent.lowercased()
            return FileSortCategory.allCases.first { $0.downloadsSubfolder.lowercased() == last } ?? .misc
        }
        return .misc
    }

    private func matchesFilter(_ card: SuggestionCardModel) -> Bool {
        guard let filter = filterCategory else { return true }
        return categorize(card) == filter
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    @ViewBuilder
    private func filterButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(label, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            Button(label, action: action).buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: - Scan logic

    nonisolated private static func performScan(
        sources: [URL],
        includeSubfolders: Bool
    ) async throws -> ScanResult {
        let fm = FileManager.default
        var allFiles: [URL] = []

        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
                if includeSubfolders {
                    if let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: options) {
                        for case let url as URL in enumerator {
                            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                                allFiles.append(url)
                            }
                        }
                    }
                } else {
                    let entries = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: options)) ?? []
                    allFiles.append(contentsOf: entries.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
                }
            } else {
                allFiles.append(source)
            }
        }

        let fallbackRoot = sources.first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let predictor = DestinationPredictor(fallbackRoot: fallbackRoot)
        let resolver: InboxRootResolver = { category in fallbackRoot.appendingPathComponent(category.downloadsSubfolder, isDirectory: true) }
        let engine = SuggestionEngine(
            adapters: [
                HeuristicSuggestionAdapter(inboxRoot: resolver, predictor: predictor),
                FoundationModelsSuggestionAdapter(inboxRoot: resolver),
            ]
        )
        let store = SuggestionStore.shared

        var cards: [SuggestionCardModel] = []
        var alreadyDecided = 0
        var hashBySHA: [String: URL] = [:]
        var dupeGroups: [String: [URL]] = [:]

        for url in allFiles {
            guard let suggestions = try? await engine.suggest(for: url) else { continue }
            for s in suggestions {
                if store.decision(for: s) != nil {
                    alreadyDecided += 1
                    continue
                }
                cards.append(SuggestionCardModel(suggestion: s))
            }
            // Duplicate detection: group by SHA-256
            if let ingested = try? await IngestionPipeline().ingest(url),
               let hash = ingested.hashed?.sha256 {
                if let existing = hashBySHA[hash] {
                    dupeGroups[hash, default: [existing]].append(url)
                } else {
                    hashBySHA[hash] = url
                }
            }
        }

        let duplicates = dupeGroups.map { (_, urls) in
            DuplicateGroup(files: urls)
        }

        return ScanResult(cards: cards, duplicates: duplicates, fileCount: allFiles.count, alreadyDecided: alreadyDecided)
    }
}

// MARK: - Models

private struct ScanResult {
    let cards: [SuggestionCardModel]
    let duplicates: [DuplicateGroup]
    let fileCount: Int
    let alreadyDecided: Int
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var files: [URL]
    var resolved: Bool = false
}


// MARK: - Suggestion Row (multi-candidate)

private struct SuggestionRow: View {
    @Binding var card: SuggestionCardModel
    /// All suggestions for the same source file (multiple candidates from predictor).
    let siblings: [Suggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File info line
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.tint)
                Text(card.suggestion.source.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if card.localDecision != .pending {
                    resultBadge
                }
            }

            // Candidate destinations (if pending)
            if card.localDecision == .pending {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(siblings, id: \.id) { candidate in
                        candidateButton(candidate)
                    }
                    otherButton
                }

                HStack {
                    Spacer()
                    Button("Skip") { skip() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    @ViewBuilder
    private func candidateButton(_ candidate: Suggestion) -> some View {
        Button {
            applyCandidate(candidate)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(shortenPath(destinationPath(candidate)))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(candidate.reasoning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let conf = candidate.confidence {
                    Text("\(Int(conf * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var otherButton: some View {
        Button {
            pickOther()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.caption)
                Text("Other…")
                    .font(.caption)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var resultBadge: some View {
        if let result = card.executionResult {
            Label(shortenPath(result), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if let error = card.executionError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else if card.localDecision == .skipped {
            Text("Skipped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func applyCandidate(_ candidate: Suggestion) {
        let executor = SuggestionExecutor()
        let result = executor.execute(candidate)
        switch result.outcome {
        case .success(let path):
            card.localDecision = .applied
            card.executionResult = path
            SuggestionStore.shared.record(candidate, decision: .accepted)
        case .kept:
            card.localDecision = .applied
            card.executionResult = "(kept)"
            SuggestionStore.shared.record(candidate, decision: .accepted)
        case .failure(let reason):
            card.executionError = reason
        }
    }

    private func pickOther() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Move here"
        if panel.runModal() == .OK, let dest = panel.url {
            let custom = Suggestion(
                source: card.suggestion.source,
                action: .move(to: dest),
                reasoning: "You chose this folder"
            )
            applyCandidate(custom)
        }
    }

    private func skip() {
        card.localDecision = .skipped
        SuggestionStore.shared.record(card.suggestion, decision: .snoozed)
    }

    private func destinationPath(_ s: Suggestion) -> String {
        if case .move(let dest) = s.action { return dest.path }
        return "?"
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Duplicate Card

private struct DuplicateCard: View {
    @Binding var group: DuplicateGroup

    var body: some View {
        if group.resolved { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Label("\(group.files.count) identical files", systemImage: "doc.on.doc.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                ForEach(group.files, id: \.self) { url in
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Keep newest") { resolveKeepNewest() }
                        .controlSize(.small)
                    Button("Keep first") { resolveKeepFirst() }
                        .controlSize(.small)
                    Button("Keep all") { group.resolved = true }
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3)))
        )
    }

    private func resolveKeepNewest() {
        let fm = FileManager.default
        let sorted = group.files.sorted { a, b in
            let da = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
            let db = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
            return da > db
        }
        trashAllExcept(sorted.first)
    }

    private func resolveKeepFirst() {
        trashAllExcept(group.files.first)
    }

    private func trashAllExcept(_ keep: URL?) {
        let fm = FileManager.default
        for url in group.files where url != keep {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        group.resolved = true
    }
}

// MARK: - Card Model (reused)

struct SuggestionCardModel: Identifiable {
    let id: UUID
    let suggestion: Suggestion
    var localDecision: LocalDecision = .pending
    var executionResult: String? = nil
    var executionError: String? = nil

    enum LocalDecision: Equatable {
        case pending, applied, skipped, rejected
    }

    init(suggestion: Suggestion) {
        self.id = suggestion.id
        self.suggestion = suggestion
    }
}
