import SwiftUI
import SwiftData
import QuickLook



struct ContentSummary: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var summary: String?
    var keywords: [String]?
    var textFileURL: URL?
    var isProcessing: Bool = false
    var processingProgress: String = ""
    
    init(id: UUID = UUID(), url: URL, summary: String? = nil, keywords: [String]? = nil, textFileURL: URL? = nil, isProcessing: Bool = false, processingProgress: String = "") {
        self.id = id
        self.url = url
        self.summary = summary
        self.keywords = keywords
        self.textFileURL = textFileURL
        self.isProcessing = isProcessing
        self.processingProgress = processingProgress
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersistentContentSummary.dateProcessed, order: .reverse) private var persistentSummaries: [PersistentContentSummary]
    @Query private var appSettings: [AppSettings]
    
    @State private var monitoredFolders: [URL] = []
    @State private var contentSummaries: [ContentSummary] = []
    @State private var selectedSummary: ContentSummary?
    @State private var isTargeted = false
    @State private var showingSettings = false
    @State private var directoryMonitors: [URL: DirectoryMonitor] = [:]
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var previewURL: URL?
    @State private var isProcessing: Bool = false
    @State private var systemStatus: SystemStatus = .loading
    @State private var searchText: String = ""
    @State private var showCopyToast = false
    @State private var showSidebar = true
    @State private var quickLookAccessingURL: URL?
    @State private var isSearching: Bool = false
    
    // Settings computed from SwiftData
    private var currentSettings: AppSettings {
        appSettings.first ?? AppSettings()
    }
    
    private var ocrLanguage: String { currentSettings.ocrLanguage }
    private var openAIModel: String { currentSettings.openAIModel }
    private var customPrompt: String { currentSettings.customPrompt }
    private var useOllama: Bool { currentSettings.useOllama }
    private var ollamaModel: String { currentSettings.ollamaModel }
    private var ollamaProcessingMode: String { currentSettings.ollamaProcessingMode }
    private var ollamaAPIURL: String { currentSettings.ollamaAPIURL }
    
    private let contentProcessor = ContentProcessor()
    private let supportedExtensions = ["pdf", "png", "jpg", "jpeg", "tiff"]

    private var summarizationService: SummarizationService {
        if useOllama {
            return OllamaService()
        } else {
            return OpenAIService()
        }
    }
    
    // MARK: - SwiftData Operations
    private func loadDataFromStorage() {
        print("📂 Loading data from storage...")
        
        // Load content summaries from SwiftData
        let validSummaries = persistentSummaries.compactMap { persistentSummary in
            // Check if file still exists
            if FileManager.default.fileExists(atPath: persistentSummary.filePath) {
                return persistentSummary.toContentSummary()
            } else {
                return nil
            }
        }
        
        // Load monitored folders from settings
        let validFolders = currentSettings.monitoredFolderPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
        
        // Update UI
        contentSummaries = validSummaries
        monitoredFolders = validFolders
        
        print("📊 Loaded \(validSummaries.count) summaries and \(validFolders.count) folders")
        
        // Clean up stuck/old documents
        cleanupStuckDocuments()
        
        // Start monitoring existing folders
        for folder in monitoredFolders {
            startMonitoring(url: folder)
        }
        
        // Clean up orphaned entries from database
        let orphanedSummaries = persistentSummaries.filter { persistentSummary in
            !FileManager.default.fileExists(atPath: persistentSummary.filePath)
        }
        
        if !orphanedSummaries.isEmpty {
            print("🗑️ Cleaning up \(orphanedSummaries.count) orphaned summaries")
            for orphaned in orphanedSummaries {
                modelContext.delete(orphaned)
            }
            
            do {
                try modelContext.save()
                print("✅ Cleaned up orphaned summaries")
            } catch {
                print("❌ Failed to clean up orphaned summaries: \(error)")
            }
        }
    }
    
    private func cleanupStuckDocuments() {
        // Find documents that are stuck in processing state
        let stuckDocuments = contentSummaries.filter { summary in
            summary.isProcessing && summary.summary == nil
        }
        
        if !stuckDocuments.isEmpty {
            print("🔧 Found \(stuckDocuments.count) stuck documents, cleaning up...")
            
            // Remove stuck documents from UI
            contentSummaries.removeAll { summary in
                stuckDocuments.contains { $0.id == summary.id }
            }
            
            // Remove from database
            for stuckDoc in stuckDocuments {
                if let persistentDoc = persistentSummaries.first(where: { $0.id == stuckDoc.id }) {
                    modelContext.delete(persistentDoc)
                }
            }
            
            do {
                try modelContext.save()
                print("✅ Cleaned up stuck documents")
            } catch {
                print("❌ Failed to clean up stuck documents: \(error)")
            }
        }
    }
    
    private func resetDatabase() {
        print("🗑️ Resetting database...")
        
        // Clear UI
        contentSummaries.removeAll()
        
        // Delete all persistent summaries
        for summary in persistentSummaries {
            modelContext.delete(summary)
        }
        
        do {
            try modelContext.save()
            print("✅ Database reset successfully")
        } catch {
            print("❌ Failed to reset database: \(error)")
        }
    }
    
    private func deleteDocument(_ summary: ContentSummary) {
        print("🗑️ Deleting document: \(summary.url.lastPathComponent)")
        
        // Remove from UI
        contentSummaries.removeAll { $0.id == summary.id }
        
        // Clear selection if this was the selected document
        if selectedSummary?.id == summary.id {
            selectedSummary = nil
        }
        
        // Remove from database
        if let persistentDoc = persistentSummaries.first(where: { $0.id == summary.id }) {
            modelContext.delete(persistentDoc)
            
            do {
                try modelContext.save()
                print("✅ Document deleted successfully")
            } catch {
                print("❌ Failed to delete document from database: \(error)")
            }
        }
    }
    
    private func openQuickLookPreview(for url: URL) {
        // Check if file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ File not found for QuickLook: \(url.path)")
            return
        }
        
        // Stop any previous security-scoped access
        if let previousURL = quickLookAccessingURL {
            previousURL.stopAccessingSecurityScopedResource()
            print("📄 Stopped previous security-scoped access")
        }
        
        // Start accessing the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        
        if accessing {
            print("📄 Starting QuickLook preview for: \(url.lastPathComponent)")
            quickLookAccessingURL = url
            previewURL = url
        } else {
            print("❌ Failed to start security-scoped access for: \(url.path)")
            quickLookAccessingURL = nil
            // Try to set preview URL anyway in case the file is accessible
            previewURL = url
        }
    }
    
    private func saveContentSummary(_ summary: ContentSummary) {
        // Check if already exists
        if let existingPersistent = persistentSummaries.first(where: { $0.id == summary.id }) {
            existingPersistent.update(from: summary)
        } else {
            let newPersistent = summary.toPersistentModel()
            modelContext.insert(newPersistent)
        }
        
        do {
            try modelContext.save()
            print("✅ Successfully saved content summary for: \(summary.url.lastPathComponent)")
        } catch {
            print("❌ Failed to save content summary: \(error)")
        }
    }
    
    private func ensureSettingsExist() {
        if appSettings.isEmpty {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            do {
                try modelContext.save()
                print("✅ Created initial settings")
            } catch {
                print("❌ Failed to create initial settings: \(error)")
            }
        }
    }
    
    private func updateSettings(_ updateBlock: (AppSettings) -> Void) {
        let settings = appSettings.first ?? AppSettings()
        if appSettings.isEmpty {
            modelContext.insert(settings)
        }
        updateBlock(settings)
        settings.lastUpdated = Date()
        do {
            try modelContext.save()
            print("✅ Successfully updated settings")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }
    
    // MARK: - Computed Properties
    private var filteredContentSummaries: [ContentSummary] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return contentSummaries
        }
        
        let searchTerms = searchText.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return contentSummaries.filter { summary in
            // Search in filename
            let filename = summary.url.lastPathComponent.lowercased()
            let filenameMatches = searchTerms.allSatisfy { term in
                filename.contains(term)
            }
            
            // Search in keywords
            let keywordMatches = searchTerms.allSatisfy { term in
                summary.keywords?.compactMap { $0.lowercased() }.joined(separator: " ").contains(term) ?? false
            }
            
            // Search in summary content
            let summaryMatches = searchTerms.allSatisfy { term in
                summary.summary?.lowercased().contains(term) ?? false
            }
            
            return filenameMatches || keywordMatches || summaryMatches
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Bar
            HStack {
                // Sidebar Toggle Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSidebar.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .buttonStyle(MacOSButtonStyle(isSecondary: true))
                .help("Toggle Sidebar")
                
                // Menu Button
                Menu {
                    Button("Settings") {
                        showingSettings.toggle()
                    }
                    
                    Divider()
                    
                    Button("Reset Database") {
                        resetDatabase()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .buttonStyle(MacOSButtonStyle(isSecondary: true))
                .help("Settings & Options")
                
                Spacer()
                
                // App Title
                
                Spacer()
                
                // Empty space to balance the layout (no duplicate status indicator)
                HStack {
                    // This space balances the left side buttons
                }
                .frame(width: 120) // Approximate width of the left buttons
            }
            .padding(.horizontal, DesignSystem.spacingL)
            .padding(.vertical, DesignSystem.spacingM)
            .background(DesignSystem.sectionHeaderBackground)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(DesignSystem.separatorColor)
                    .opacity(0.3),
                alignment: .bottom
            )
            
            // MARK: - Main Content
            HSplitView {
                // Left Panel - Monitored Folders (Collapsible)
                if showSidebar {
                    VStack(spacing: 0) {
                    // Header
                    VStack(spacing: DesignSystem.spacingS) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(DesignSystem.primaryBlue)
                                .font(.system(size: 20, weight: .semibold))
                            Text("Monitored Folders")
                                .font(DesignSystem.titleMedium)
                                .foregroundColor(DesignSystem.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                        .padding(.top, DesignSystem.spacingL)
                        .padding(.bottom, DesignSystem.spacingS)
                        
                        Divider()
                            .background(DesignSystem.separatorColor)
                    }
                
                // Folders List
                if monitoredFolders.isEmpty {
                    VStack(spacing: DesignSystem.spacingL) {
                        Spacer()
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(DesignSystem.textTertiary)
                        
                        VStack(spacing: DesignSystem.spacingS) {
                            Text("No folders monitored")
                                .font(DesignSystem.titleSmall)
                                .foregroundColor(DesignSystem.textSecondary)
                            Text("Add folders to automatically process new files")
                                .font(DesignSystem.body)
                                .foregroundColor(DesignSystem.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.spacingXL)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.spacingS) {
                            ForEach(monitoredFolders, id: \.self) { folder in
                                FolderRowView(folder: folder) {
                                    removeFolder(folder)
                                }
                            }
                        }
                        .padding(.horizontal, DesignSystem.spacingM)
                        .padding(.vertical, DesignSystem.spacingL)
                    }
                }
                
                // Add Folder Button
                VStack(spacing: DesignSystem.spacingM) {
                    Divider()
                        .background(DesignSystem.separatorColor)
                    
                    Button(action: selectFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                            .font(DesignSystem.body)
                    }
                    .buttonStyle(MacOSButtonStyle())
                    .padding(.horizontal, DesignSystem.spacingL)
                    .padding(.bottom, DesignSystem.spacingL)
                }
                }
                .background(DesignSystem.backgroundSecondary)
                .frame(minWidth: 280)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            // MARK: - Main Content
            VStack(spacing: 0) {
                // Top Section - File List and Summary Detail
                HSplitView {
                    // File List
                    VStack(spacing: 0) {
                        // Files Header with accent
                        VStack(spacing: DesignSystem.spacingS) {
                            HStack {
                                HStack(spacing: DesignSystem.spacingS) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(DesignSystem.primaryBlue)
                                        .font(.system(size: 20, weight: .semibold))
                                    Text("Documents")
                                        .font(DesignSystem.titleMedium)
                                        .foregroundColor(DesignSystem.textPrimary)
                                }
                                Spacer()
                                Text(searchText.isEmpty ? "\(contentSummaries.count) files" : "\(filteredContentSummaries.count) of \(contentSummaries.count)")
                                    .font(DesignSystem.caption)
                                    .foregroundColor(DesignSystem.textSecondary)
                                    .padding(.horizontal, DesignSystem.spacingS)
                                    .padding(.vertical, DesignSystem.spacingXS)
                                    .background(DesignSystem.primaryBlue.opacity(0.1))
                                    .cornerRadius(DesignSystem.cornerRadiusS)
                            }
                            .padding(.horizontal, DesignSystem.spacingL)
                            .padding(.top, DesignSystem.spacingL)
                            .padding(.bottom, DesignSystem.spacingS)
                            .background(DesignSystem.sectionHeaderBackground)
                            
                            // Enhanced Search Bar
                            VStack(spacing: DesignSystem.spacingXS) {
                                HStack(spacing: DesignSystem.spacingS) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(searchText.isEmpty ? DesignSystem.textTertiary : DesignSystem.primaryBlue)
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    TextField("Search documents, keywords, or content...", text: $searchText)
                                        .font(DesignSystem.body)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .onSubmit {
                                            isSearching = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                isSearching = false
                                            }
                                        }
                                    
                                    if !searchText.isEmpty {
                                        Button(action: {
                                            searchText = ""
                                            selectedSummary = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(DesignSystem.textTertiary)
                                                .font(.system(size: 16, weight: .medium))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, DesignSystem.spacingL)
                                .padding(.vertical, DesignSystem.spacingM)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                        .fill(DesignSystem.backgroundTertiary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                                .stroke(searchText.isEmpty ? DesignSystem.separatorColor : DesignSystem.primaryBlue.opacity(0.4), lineWidth: 1.5)
                                        )
                                        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
                                )
                                
                                // Search results indicator
                                if !searchText.isEmpty {
                                    HStack {
                                        Text("Found \(filteredContentSummaries.count) of \(contentSummaries.count) documents")
                                            .font(DesignSystem.caption)
                                            .foregroundColor(DesignSystem.textSecondary)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, DesignSystem.spacingL)
                            .padding(.bottom, DesignSystem.spacingM)
                            
                            Divider()
                                .background(DesignSystem.separatorColor)
                        }
                        
                        ZStack {
                            if filteredContentSummaries.isEmpty && !searchText.isEmpty {
                                // No search results
                                VStack(spacing: DesignSystem.spacingXL) {
                                    Spacer()
                                    
                                    VStack(spacing: DesignSystem.spacingL) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 64, weight: .light))
                                            .foregroundColor(DesignSystem.textTertiary)
                                        
                                        VStack(spacing: DesignSystem.spacingS) {
                                            Text("No Results Found")
                                                .font(DesignSystem.titleSmall)
                                                .foregroundColor(DesignSystem.textSecondary)
                                            
                                            Text("No documents match '\(searchText)'")
                                                .font(DesignSystem.body)
                                                .foregroundColor(DesignSystem.textTertiary)
                                                .multilineTextAlignment(.center)
                                            
                                            Text("Try searching with different keywords or check summary content")
                                                .font(DesignSystem.bodySmall)
                                                .foregroundColor(DesignSystem.textTertiary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                    
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Text("Clear Search")
                                            .font(DesignSystem.body)
                                    }
                                    .buttonStyle(MacOSButtonStyle(isSecondary: true))
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, DesignSystem.spacingXXL)
                            } else if contentSummaries.isEmpty {
                                // Empty state with drag and drop
                                VStack(spacing: DesignSystem.spacingXL) {
                                    Spacer()
                                    
                                    VStack(spacing: DesignSystem.spacingL) {
                                        Image(systemName: "square.and.arrow.down.on.square")
                                            .font(.system(size: 64, weight: .light))
                                            .foregroundColor(isTargeted ? DesignSystem.primaryBlue : DesignSystem.textTertiary)
                                        
                                        VStack(spacing: DesignSystem.spacingS) {
                                            Text("Drag & Drop Files Here")
                                                .font(DesignSystem.titleSmall)
                                                .foregroundColor(isTargeted ? DesignSystem.primaryBlue : DesignSystem.textSecondary)
                                            
                                            Text("Supports PDF, PNG, JPG, JPEG, TIFF files")
                                                .font(DesignSystem.body)
                                                .foregroundColor(DesignSystem.textTertiary)
                                                .multilineTextAlignment(.center)
                                            
                                            Text("Or add monitored folders below")
                                                .font(DesignSystem.bodySmall)
                                                .foregroundColor(DesignSystem.textTertiary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                    .padding(DesignSystem.spacingXL)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                            .fill(isTargeted ? DesignSystem.primaryBlue.opacity(0.1) : DesignSystem.backgroundTertiary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                                    .stroke(
                                                        isTargeted ? DesignSystem.primaryBlue : DesignSystem.separatorColor,
                                                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                                    )
                                            )
                                    )
                                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, DesignSystem.spacingXXL)
                            } else {
                                // Documents list
                                ScrollView {
                                    LazyVStack(spacing: DesignSystem.spacingXS) {
                                        ForEach(filteredContentSummaries, id: \.id) { summary in
                                            DocumentRowView(
                                                summary: summary, 
                                                isSelected: selectedSummary?.id == summary.id,
                                                searchText: searchText,
                                                onDelete: {
                                                    deleteDocument(summary)
                                                }
                                            )
                                                .onTapGesture {
                                                    selectedSummary = summary
                                                }
                                                .onTapGesture(count: 2) {
                                                    openQuickLookPreview(for: summary.url)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.spacingM)
                                    .padding(.vertical, DesignSystem.spacingL)
                                }
                                .focusable()
                                .focusEffectDisabled()
                                .onKeyPress(.space) { 
                                    if let selectedURL = selectedSummary?.url {
                                        openQuickLookPreview(for: selectedURL)
                                        return .handled
                                    }
                                    return .ignored
                                }
                                
                                // Drag and drop overlay when files exist
                                if isTargeted {
                                    VStack(spacing: DesignSystem.spacingL) {
                                        Spacer()
                                        
                                        VStack(spacing: DesignSystem.spacingM) {
                                            Image(systemName: "plus.square.dashed")
                                                .font(.system(size: 48, weight: .light))
                                                .foregroundColor(DesignSystem.primaryBlue)
                                            
                                            Text("Drop to Add Files")
                                                .font(DesignSystem.titleSmall)
                                                .foregroundColor(DesignSystem.primaryBlue)
                                        }
                                        .padding(DesignSystem.spacingXL)
                                        .background(
                                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                                .fill(DesignSystem.primaryBlue.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                                                        .stroke(DesignSystem.primaryBlue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                                )
                                        )
                                        
                                        Spacer()
                                    }
                                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
                                }
                            }
                        }
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleDrop(providers: providers)
                            return true
                        }
                    }
                    .frame(minWidth: 320)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                DesignSystem.backgroundSecondary,
                                DesignSystem.documentsSectionAccent
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Summary Detail View with accent
                    VStack(spacing: 0) {
                        if let selectedSummary = selectedSummary {
                            VStack(spacing: 0) {
                                // Summary Header
                                HStack {
                                    HStack(spacing: DesignSystem.spacingS) {
                                        Image(systemName: "doc.richtext")
                                            .foregroundColor(DesignSystem.accentTeal)
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Summary")
                                            .font(DesignSystem.titleMedium)
                                            .foregroundColor(DesignSystem.textPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, DesignSystem.spacingL)
                                .padding(.vertical, DesignSystem.spacingM)
                                .background(DesignSystem.sectionHeaderBackground)
                                
                                SummaryDetailView(
                                    summary: selectedSummary, 
                                    useOllama: useOllama, 
                                    ollamaProcessingMode: ollamaProcessingMode,
                                    searchText: searchText,
                                    showCopyToast: $showCopyToast
                                )
                            }
                        } else {
                            EmptyDetailView()
                        }
                    }
                    .frame(minWidth: 400)
                    .background(DesignSystem.backgroundTertiary)
                }
                .frame(minHeight: 400)
            }
            .navigationTitle(getNavigationTitle())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    statusIndicator
                }
            }
            .quickLookPreview($previewURL)
            .onChange(of: previewURL) { _, newValue in
                // Clean up security-scoped access when preview is dismissed
                if newValue == nil, let accessingURL = quickLookAccessingURL {
                    accessingURL.stopAccessingSecurityScopedResource()
                    quickLookAccessingURL = nil
                    print("📄 Cleaned up security-scoped access after QuickLook dismissed")
                }
            }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            ensureSettingsExist()
            loadDataFromStorage()
            checkSystemStatus()
        }
        .onDisappear {
            stopAllMonitors()
            
            // Clean up QuickLook security-scoped access
            if let accessingURL = quickLookAccessingURL {
                accessingURL.stopAccessingSecurityScopedResource()
                quickLookAccessingURL = nil
                print("📄 Cleaned up QuickLook security-scoped access on app disappear")
            }
        }
        .overlay(
            // Copy Toast Notification
            VStack {
                Spacer()
                if showCopyToast {
                    HStack(spacing: DesignSystem.spacingS) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.accentGreen)
                            .font(.system(size: 16, weight: .medium))
                        Text("Summary copied to clipboard")
                            .font(DesignSystem.body)
                            .foregroundColor(DesignSystem.textPrimary)
                    }
                    .padding(.horizontal, DesignSystem.spacingL)
                    .padding(.vertical, DesignSystem.spacingM)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusL)
                            .fill(DesignSystem.backgroundTertiary)
                            .shadow(color: DesignSystem.shadowMedium, radius: 8, x: 0, y: 4)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showCopyToast)
                }
            }
            .padding(.bottom, DesignSystem.spacingXL)
        )
    }
    
    private func getNavigationTitle() -> String {
        return "PDF Summarizer"
    }
    
    private var statusIndicator: some View {
        HStack(spacing: DesignSystem.spacingXS) {
            if useOllama {
                switch systemStatus {
                case .ready:
                    Circle()
                        .fill(DesignSystem.accentGreen)
                        .frame(width: 8, height: 8)
                case .error:
                    Circle()
                        .fill(DesignSystem.accentRed)
                        .frame(width: 8, height: 8)
                case .loading:
                    Circle()
                        .fill(DesignSystem.accentOrange)
                        .frame(width: 8, height: 8)
                }
            } else {
                Circle()
                    .fill(DesignSystem.accentGreen)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private func checkSystemStatus() {
        if useOllama {
            Task {
                let status = await checkOllamaStatus()
                await MainActor.run {
                    systemStatus = status
                }
            }
        } else {
            systemStatus = .ready // OpenAI is always considered ready if API key is set
        }
    }
    
    private func checkOllamaStatus() async -> SystemStatus {
        do {
            let url = URL(string: ollamaAPIURL.replacingOccurrences(of: "/api/chat", with: "/api/tags"))!
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 ? .ready : .error
            }
            return .error
        } catch {
            return .error
        }
    }
    
    private func removeFolder(_ folder: URL) {
        if let index = monitoredFolders.firstIndex(of: folder) {
            monitoredFolders.remove(at: index)
            directoryMonitors[folder]?.stop()
            directoryMonitors.removeValue(forKey: folder)
            
            // Stop accessing security-scoped resource
            folder.stopAccessingSecurityScopedResource()
            print("📁 Stopped accessing security-scoped resource: \(folder.path)")
            
            // Save to SwiftData
            updateSettings { settings in
                settings.monitoredFolderPaths = monitoredFolders.map { $0.path }
            }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                monitoredFolders.append(url)
                startMonitoring(url: url)
                
                // Save to SwiftData
                updateSettings { settings in
                    settings.monitoredFolderPaths = monitoredFolders.map { $0.path }
                }
                
                // Process existing files in the folder
                Task {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                        for fileURL in contents {
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) && !contentSummaries.contains(where: { $0.url == fileURL }) {
                                await processFile(url: fileURL)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to process existing files: \(error.localizedDescription)"
                            showingErrorAlert = true
                        }
                    }
                }
            }
        }
    }

    private func startMonitoring(url: URL) {
        // Start accessing the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        
        let monitor = DirectoryMonitor(url: url)
        monitor.onFileAdded = { fileURL in
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) && !self.contentSummaries.contains(where: { $0.url == fileURL }) {
                Task {
                    await processFile(url: fileURL)
                }
            }
        }
        monitor.start()
        directoryMonitors[url] = monitor
        
        // Store the access state for cleanup later
        if accessing {
            print("📁 Started accessing security-scoped resource: \(url.path)")
        }
    }
    
    private func stopAllMonitors() {
        directoryMonitors.values.forEach { $0.stop() }
        
        // Stop accessing security-scoped resources
        for url in directoryMonitors.keys {
            url.stopAccessingSecurityScopedResource()
            print("📁 Stopped accessing security-scoped resource: \(url.path)")
        }
        
        directoryMonitors.removeAll()
    }
    
    private func processFile(url: URL) async {
        print("🔄 Starting to process file: \(url.lastPathComponent)")
        // Start accessing the security-scoped resource for this file
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        // Always start with summary = nil and isProcessing = true
        let newSummary = ContentSummary(url: url, summary: nil, isProcessing: true, processingProgress: "Starting...")
        await MainActor.run {
            self.contentSummaries.append(newSummary)
            self.isProcessing = true
        }
        // Save initial summary to SwiftData
        await MainActor.run {
            self.saveContentSummary(newSummary)
        }
        do {
            let (summary, keywords): (String, [String])
            var textFileURL: URL?
            if useOllama {
                // Ollama: Direct file processing (no OCR)
                print("📸 Using Ollama for direct file processing with model: \(ollamaModel)")
                await MainActor.run {
                    if let index = self.contentSummaries.firstIndex(where: { $0.url == url }) {
                        self.contentSummaries[index].processingProgress = "Processing with vision model..."
                        self.contentSummaries[index].summary = nil // Ensure summary is nil while processing
                    }
                }
                (summary, keywords) = try await OllamaService().summarizeAndTag(
                    fileURL: url,
                    model: ollamaModel,
                    customPrompt: customPrompt
                )
                textFileURL = nil
                print("✅ Ollama vision processing completed for: \(url.lastPathComponent)")
            } else {
                // OpenAI: OCR workflow
                print("📝 Using OpenAI for OCR+text processing with model: \(openAIModel)")
                await MainActor.run {
                    if let index = self.contentSummaries.firstIndex(where: { $0.url == url }) {
                        self.contentSummaries[index].processingProgress = "Extracting text..."
                        self.contentSummaries[index].summary = nil // Ensure summary is nil while processing
                    }
                }
                let (text, tempTextURL) = try await contentProcessor.extractText(from: url, language: ocrLanguage)
                print("📄 OCR completed, text length: \(text.count) characters")
                await MainActor.run {
                    if let index = self.contentSummaries.firstIndex(where: { $0.url == url }) {
                        self.contentSummaries[index].processingProgress = "Generating summary..."
                        self.contentSummaries[index].summary = nil // Ensure summary is nil while processing
                    }
                }
                (summary, keywords) = try await OpenAIService().summarizeAndTag(
                    text: text,
                    model: openAIModel,
                    customPrompt: customPrompt
                )
                textFileURL = tempTextURL
                print("✅ OpenAI summarization completed for: \(url.lastPathComponent)")
            }
            if let index = self.contentSummaries.firstIndex(where: { $0.url == url }) {
                await MainActor.run {
                    self.contentSummaries[index].summary = summary
                    self.contentSummaries[index].keywords = keywords
                    self.contentSummaries[index].textFileURL = textFileURL
                    self.contentSummaries[index].isProcessing = false // Only set isProcessing false after summary is set
                    self.contentSummaries[index].processingProgress = ""
                    // Save to SwiftData
                    self.saveContentSummary(self.contentSummaries[index])
                }
                print("🎉 Successfully processed file: \(url.lastPathComponent)")
                print("📋 Summary: \(summary.prefix(100))...")
                print("🏷️ Keywords: \(keywords.joined(separator: ", "))")
            }
        } catch {
            print("❌ Error processing file \(url.lastPathComponent): \(error)")
            await MainActor.run {
                if let index = self.contentSummaries.firstIndex(where: { $0.url == url }) {
                    self.contentSummaries[index].isProcessing = false
                    self.contentSummaries[index].processingProgress = ""
                }
                if self.useOllama && error.localizedDescription.contains("Cannot connect to Ollama") {
                    self.errorMessage = "Ollama is not running. Please start Ollama with 'ollama serve' or switch to OpenAI in Settings."
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.showingErrorAlert = true
            }
        }
        await MainActor.run {
            self.isProcessing = false
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url, supportedExtensions.contains(url.pathExtension.lowercased()) {
                        if !self.contentSummaries.contains(where: { $0.url == url }) {
                            Task {
                                await processFile(url: url)
                            }
                        }
                    }
                }
            }
        }
    }


}

enum SystemStatus {
    case ready, error, loading
}

// MARK: - Folder Row View
struct FolderRowView: View {
    let folder: URL
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DesignSystem.spacingM) {
            Image(systemName: "folder.fill")
                .foregroundColor(DesignSystem.primaryBlue)
                .font(.system(size: 18, weight: .medium))
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                Text(folder.lastPathComponent)
                    .font(DesignSystem.headline)
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(1)
                Text(folder.path)
                    .font(DesignSystem.bodySmall)
                    .foregroundColor(DesignSystem.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.accentRed)
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignSystem.spacingM)
        .padding(.vertical, DesignSystem.spacingS)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                .fill(isHovered ? DesignSystem.backgroundTertiary : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Document Row View
struct DocumentRowView: View {
    let summary: ContentSummary
    let isSelected: Bool
    let searchText: String
    let onDelete: () -> Void
    @State private var isHovered = false
    
    init(summary: ContentSummary, isSelected: Bool, searchText: String = "", onDelete: @escaping () -> Void) {
        self.summary = summary
        self.isSelected = isSelected
        self.searchText = searchText
        self.onDelete = onDelete
        print("DocumentRowView init for: \(summary.url.lastPathComponent), isProcessing: \(summary.isProcessing)")
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.spacingM) {
            // File Icon
            Image(systemName: fileIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusS)
                        .fill(iconColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                // Filename with search highlighting
                if !searchText.isEmpty && summary.url.lastPathComponent.lowercased().contains(searchText.lowercased()) {
                    HighlightedText(
                        text: summary.url.lastPathComponent,
                        searchText: searchText,
                        font: DesignSystem.headline,
                        textColor: DesignSystem.textPrimary,
                        highlightColor: DesignSystem.primaryBlue.opacity(0.3)
                    )
                    .lineLimit(1)
                } else {
                    Text(summary.url.lastPathComponent)
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(1)
                }
                
                if summary.isProcessing {
                    HStack(spacing: DesignSystem.spacingXS) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(summary.processingProgress)
                            .font(DesignSystem.bodySmall)
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                } else if summary.summary != nil {
                    HStack(spacing: DesignSystem.spacingXS) {
                        Text("Summary available")
                            .font(DesignSystem.bodySmall)
                            .foregroundColor(DesignSystem.textSecondary)
                        
                        // Show matched keywords if search is active
                        if !searchText.isEmpty, let keywords = summary.keywords {
                            let matchedKeywords = keywords.filter { keyword in
                                keyword.lowercased().contains(searchText.lowercased())
                            }
                            if !matchedKeywords.isEmpty {
                                Text("• \(matchedKeywords.joined(separator: ", "))")
                                    .font(DesignSystem.bodySmall)
                                    .foregroundColor(DesignSystem.primaryBlue)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text("No summary available")
                        .font(DesignSystem.bodySmall)
                        .foregroundColor(DesignSystem.textTertiary)
                }
            }
            
            Spacer()
            
            // Delete button (visible on hover)
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.accentRed)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete document")
                .transition(.scale.combined(with: .opacity))
            }
            
            // Status indicator
            if !summary.isProcessing {
                if summary.summary != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.accentGreen)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignSystem.accentOrange)
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .padding(.horizontal, DesignSystem.spacingM)
        .padding(.vertical, DesignSystem.spacingS)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                .fill(isSelected ? DesignSystem.primaryBlue.opacity(0.05) : (isHovered ? DesignSystem.backgroundTertiary : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var fileIcon: String {
        switch summary.url.pathExtension.lowercased() {
        case "pdf":
            return "doc.fill"
        case "png", "jpg", "jpeg":
            return "photo.fill"
        case "tiff":
            return "photo.fill"
        default:
            return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch summary.url.pathExtension.lowercased() {
        case "pdf":
            return DesignSystem.accentRed
        case "png", "jpg", "jpeg", "tiff":
            return DesignSystem.primaryBlue
        default:
            return DesignSystem.textSecondary
        }
    }
}

// MARK: - Summary Detail View
struct SummaryDetailView: View {
    let summary: ContentSummary
    let useOllama: Bool
    let ollamaProcessingMode: String
    let searchText: String
    @Binding var showCopyToast: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingXL) {
                // Header
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text(summary.url.lastPathComponent)
                        .font(DesignSystem.titleMedium)
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Text(summary.url.path)
                        .font(DesignSystem.bodySmall)
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(2)
                    
                    // Quick Actions
                    HStack(spacing: DesignSystem.spacingS) {
                        if let textURL = summary.textFileURL {
                            Button(action: {
                                NSWorkspace.shared.open(textURL)
                            }) {
                                Label("Open OCR Text", systemImage: "doc.text")
                                    .font(DesignSystem.bodySmall)
                            }
                            .buttonStyle(MacOSButtonStyle(isSecondary: true))
                        }
                        
                        if let summaryText = summary.summary {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(summaryText, forType: .string)
                                showCopyToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopyToast = false
                                }
                            }) {
                                Label("Copy Summary", systemImage: "doc.on.doc")
                                    .font(DesignSystem.bodySmall)
                            }
                            .buttonStyle(MacOSButtonStyle(isSecondary: true))
                        }
                        
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([summary.url])
                        }) {
                            Label("Show in Finder", systemImage: "folder")
                                .font(DesignSystem.bodySmall)
                        }
                        .buttonStyle(MacOSButtonStyle(isSecondary: true))
                    }
                    
                    // Only show processing mode indicator if document is currently processing
                    if summary.isProcessing && useOllama {
                        HStack(spacing: DesignSystem.spacingXS) {
                            Image(systemName: ollamaProcessingMode == "vision" ? "eye.fill" : "textformat.alt")
                                .font(DesignSystem.bodySmall)
                                .foregroundColor(DesignSystem.textSecondary)
                            Text(ollamaProcessingMode == "vision" ? "Direct vision processing" : "OCR processing")
                                .font(DesignSystem.bodySmall)
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                        .padding(.horizontal, DesignSystem.spacingS)
                        .padding(.vertical, DesignSystem.spacingXS)
                        .background(DesignSystem.backgroundSecondary)
                        .cornerRadius(DesignSystem.cornerRadiusS)
                    }
                }
                .padding(.horizontal, DesignSystem.spacingXL)
                .padding(.top, DesignSystem.spacingXL)
                
                Divider()
                    .background(DesignSystem.separatorColor)
                    .padding(.horizontal, DesignSystem.spacingXL)
                
                if summary.isProcessing {
                    VStack(spacing: DesignSystem.spacingL) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(summary.processingProgress)
                            .font(DesignSystem.titleSmall)
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, DesignSystem.spacingXL)
                } else if let summaryText = summary.summary {
                    // Formatted Summary
                    FormattedSummaryView(text: summaryText, searchText: searchText)
                        .padding(.horizontal, DesignSystem.spacingXL)
                    
                    // Keywords
                    if let keywords = summary.keywords, !keywords.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                            Text("Keywords")
                                .font(DesignSystem.titleSmall)
                                .foregroundColor(DesignSystem.textPrimary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DesignSystem.spacingS) {
                                    ForEach(keywords, id: \.self) { keyword in
                                        let isMatched = !searchText.isEmpty && keyword.lowercased().contains(searchText.lowercased())
                                        Text(keyword)
                                            .font(DesignSystem.bodySmall)
                                            .foregroundColor(isMatched ? Color.white : DesignSystem.primaryBlue)
                                            .padding(.horizontal, DesignSystem.spacingS)
                                            .padding(.vertical, DesignSystem.spacingXS)
                                            .background(isMatched ? DesignSystem.primaryBlue : DesignSystem.primaryBlue.opacity(0.1))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(isMatched ? DesignSystem.primaryBlue : Color.clear, lineWidth: 2)
                                            )
                                    }
                                }
                                .padding(.horizontal, DesignSystem.spacingXL)
                            }
                        }
                        .padding(.horizontal, DesignSystem.spacingXL)
                    }
                } else {
                    VStack(spacing: DesignSystem.spacingL) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(DesignSystem.accentOrange)
                        
                        VStack(spacing: DesignSystem.spacingS) {
                            Text("Summary not available")
                                .font(DesignSystem.titleSmall)
                                .foregroundColor(DesignSystem.textSecondary)
                            Text("There was an error processing this document")
                                .font(DesignSystem.body)
                                .foregroundColor(DesignSystem.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, DesignSystem.spacingXL)
                }
                
                Spacer(minLength: DesignSystem.spacingXL)
            }
        }
        .background(DesignSystem.backgroundTertiary)
    }
}

// MARK: - Formatted Summary View
struct FormattedSummaryView: View {
    let text: String
    let searchText: String
    
    init(text: String, searchText: String = "") {
        self.text = text
        self.searchText = searchText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            Text("Summary")
                .font(DesignSystem.titleSmall)
                .foregroundColor(DesignSystem.textPrimary)
            
            // Parse and format the structured text
            ForEach(parsedSections, id: \.title) { section in
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(DesignSystem.body)
                            .foregroundColor(getSectionColor(for: section.title))
                            .fontWeight(.semibold)
                    }
                    
                    ForEach(section.items, id: \.self) { item in
                        if !searchText.isEmpty && item.lowercased().contains(searchText.lowercased()) {
                            HighlightedText(
                                text: item,
                                searchText: searchText,
                                font: DesignSystem.body,
                                textColor: DesignSystem.textBlack,
                                highlightColor: DesignSystem.primaryBlue.opacity(0.3)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, section.title.isEmpty ? 0 : DesignSystem.spacingM)
                        } else {
                            Text(item)
                                .font(DesignSystem.body)
                                .foregroundColor(DesignSystem.textBlack)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, section.title.isEmpty ? 0 : DesignSystem.spacingM)
                        }
                    }
                }
                .padding(.vertical, DesignSystem.spacingXS)
            }
        }
    }
    
    private func getSectionColor(for title: String) -> Color {
        let lowerTitle = title.lowercased()
        
        if lowerTitle.contains("key points") || lowerTitle.contains("summary") {
            return DesignSystem.primaryBlue
        } else if lowerTitle.contains("background") || lowerTitle.contains("context") {
            return DesignSystem.accentGreen
        } else if lowerTitle.contains("life application") || lowerTitle.contains("application") {
            return DesignSystem.accentOrange
        } else if lowerTitle.contains("question") || lowerTitle.contains("discussion") {
            return DesignSystem.accentPurple
        } else if lowerTitle.contains("prayer") || lowerTitle.contains("reflection") {
            return DesignSystem.accentTeal
        } else if lowerTitle.contains("conclusion") || lowerTitle.contains("takeaway") {
            return DesignSystem.accentRed
        } else {
            return DesignSystem.textPrimary
        }
    }
    
    private var parsedSections: [Section] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [Section] = []
        var currentSection = Section(title: "", items: [])
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.isEmpty {
                continue
            }
            
            // Check if it's a section header with **
            if trimmed.starts(with: "**") && trimmed.hasSuffix("**") {
                // Save previous section
                if !currentSection.items.isEmpty || !currentSection.title.isEmpty {
                    sections.append(currentSection)
                }
                // Start new section
                let title = trimmed.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = Section(title: title, items: [])
            } else if trimmed.contains("**") && trimmed.contains(":") {
                // Handle inline headers like "**Background**:"
                if !currentSection.items.isEmpty || !currentSection.title.isEmpty {
                    sections.append(currentSection)
                }
                let title = trimmed.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = Section(title: title, items: [])
            } else if let match = trimmed.firstMatch(of: /^(\d+)\.\s*(.+)/) {
                // Handle numbered sections like "1. Machine Learning"
                if !currentSection.items.isEmpty || !currentSection.title.isEmpty {
                    sections.append(currentSection)
                }
                let title = String(match.2)
                currentSection = Section(title: title, items: [])
            } else if trimmed.hasSuffix(":") && trimmed.count < 50 {
                // Handle potential section headers ending with colon
                if !currentSection.items.isEmpty || !currentSection.title.isEmpty {
                    sections.append(currentSection)
                }
                let title = trimmed.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                currentSection = Section(title: title, items: [])
            } else {
                // Regular content
                currentSection.items.append(trimmed)
            }
        }
        
        // Add the last section
        if !currentSection.items.isEmpty || !currentSection.title.isEmpty {
            sections.append(currentSection)
        }
        
        // If no sections were found, treat the entire text as one section
        if sections.isEmpty {
            sections.append(Section(title: "", items: [text]))
        }
        
        return sections
    }
    
    struct Section {
        let title: String
        var items: [String]
    }
}

// MARK: - Empty Detail View
struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: DesignSystem.spacingXL) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundColor(DesignSystem.textTertiary)
            
            VStack(spacing: DesignSystem.spacingS) {
                Text("Select a document")
                    .font(DesignSystem.titleMedium)
                    .foregroundColor(DesignSystem.textSecondary)
                
                Text("Choose a document from the list to view its summary")
                    .font(DesignSystem.body)
                    .foregroundColor(DesignSystem.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.backgroundTertiary)
    }
}





// MARK: - Highlighted Text Component
struct HighlightedText: View {
    let text: String
    let searchText: String
    let font: Font
    let textColor: Color
    let highlightColor: Color
    
    var body: some View {
        let searchTerms = searchText.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if searchTerms.isEmpty {
            Text(text)
                .font(font)
                .foregroundColor(textColor)
        } else {
            let attributedString = createAttributedString()
            Text(AttributedString(attributedString))
        }
    }
    
    private func createAttributedString() -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: text.count)
        
        // Set base attributes
        attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 16, weight: .semibold), range: range)
        attributedString.addAttribute(.foregroundColor, value: NSColor(textColor), range: range)
        
        // Highlight search terms
        let searchTerms = searchText.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        for term in searchTerms {
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            
            var searchIndex = 0
            while searchIndex < text.count {
                let remainingRange = NSRange(location: searchIndex, length: text.count - searchIndex)
                let foundRange = (text as NSString).range(of: term, options: options, range: remainingRange)
                
                if foundRange.location == NSNotFound {
                    break
                }
                
                attributedString.addAttribute(.backgroundColor, value: NSColor(highlightColor), range: foundRange)
                searchIndex = foundRange.location + foundRange.length
            }
        }
        
        return attributedString
    }
}

#Preview {
    ContentView()
}
