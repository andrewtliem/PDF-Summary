import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.presentationMode) var presentationMode
    @Query private var appSettings: [AppSettings]
    
    @State private var apiKey = ""
    @AppStorage("openAIKey") private var openAIKeyStorage: String = ""
    @State private var ocrLanguage = "English"
    @State private var openAIModel = "gpt-3.5-turbo"
    @State private var customPrompt = "You are an expert text analyzer. Read the following text carefully. Provide a clear, concise, and well-structured summary in 3–4 short paragraphs, highlighting the main ideas and important details without repeating phrases or filler words. Your response must be a very details, flat JSON object with only two keys: 'summary' and 'keywords'."
    @State private var useOllama = false
    @State private var ollamaAPIURL = "http://localhost:11434/api/chat"
    @State private var ollamaModel = "llama3.1:8b"
    @State private var ollamaProcessingMode = "fast" // "fast" or "vision"
    
    private var currentSettings: AppSettings {
        appSettings.first ?? AppSettings()
    }
    
    private let languages = ["English", "Indonesian"]
    private let openAIModels = ["gpt-3.5-turbo", "gpt-4", "gpt-4o"]
    
    // MARK: - SwiftData Operations
    private func loadSettings() {
        let settings = currentSettings
        apiKey = settings.openAIAPIKey
        ocrLanguage = settings.ocrLanguage
        openAIModel = settings.openAIModel
        customPrompt = settings.customPrompt
        useOllama = settings.useOllama
        ollamaAPIURL = settings.ollamaAPIURL
        ollamaModel = settings.ollamaModel
        ollamaProcessingMode = settings.ollamaProcessingMode
    }
    
    private func saveSettings() {
        let settings = appSettings.first ?? AppSettings()
        if appSettings.isEmpty {
            modelContext.insert(settings)
        }
        
        settings.openAIAPIKey = apiKey
        settings.ocrLanguage = ocrLanguage
        settings.openAIModel = openAIModel
        settings.customPrompt = customPrompt
        settings.useOllama = useOllama
        settings.ollamaAPIURL = ollamaAPIURL
        settings.ollamaModel = ollamaModel
        settings.ollamaProcessingMode = ollamaProcessingMode
        settings.lastUpdated = Date()
        // Sync to @AppStorage for OpenAIService
        openAIKeyStorage = apiKey
        try? modelContext.save()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: DesignSystem.spacingL) {
                    VStack(spacing: DesignSystem.spacingS) {
                        Image(systemName: "gear")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(DesignSystem.primaryBlue)
                        
                        Text("Settings")
                            .font(DesignSystem.titleLarge)
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Configure your PDF summarization preferences")
                            .font(DesignSystem.body)
                            .foregroundColor(DesignSystem.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Divider()
                        .background(DesignSystem.separatorColor)
                }
                .padding(.top, DesignSystem.spacingXXL)
                .padding(.horizontal, DesignSystem.spacingXL)
                .padding(.bottom, DesignSystem.spacingXL)
                
                VStack(spacing: DesignSystem.spacingXL) {
                    // Service Selection
                    ServiceSelectionCard(useOllama: $useOllama)
                    
                    // Service Configuration
                    if useOllama {
                        OllamaConfigurationCard(
                            apiURL: $ollamaAPIURL,
                            model: $ollamaModel,
                            processingMode: $ollamaProcessingMode
                        )
                    } else {
                        OpenAIConfigurationCard(
                            apiKey: $apiKey,
                            model: $openAIModel
                        )
                    }
                    
                    // OCR Language
                    OCRLanguageCard(selectedLanguage: $ocrLanguage, languages: languages)
                    
                    // Custom Prompt
                    CustomPromptCard(prompt: $customPrompt)
                    
                    // Save Button
                    VStack(spacing: DesignSystem.spacingL) {
                        Divider()
                            .background(DesignSystem.separatorColor)
                        
                        HStack {
                            Spacer()
                                                    Button("Save Settings") {
                            saveSettings()
                            presentationMode.wrappedValue.dismiss()
                        }
                            .buttonStyle(MacOSButtonStyle())
                            .controlSize(.large)
                        }
                    }
                    .padding(.top, DesignSystem.spacingL)
                }
                .padding(.horizontal, DesignSystem.spacingXL)
                .padding(.bottom, DesignSystem.spacingXXL)
            }
        }
        .background(DesignSystem.settingsBackground)
        .frame(minWidth: 700, minHeight: 800)
        .onAppear {
            loadSettings()
        }
    }
}

// MARK: - Service Selection Card
struct ServiceSelectionCard: View {
    @Binding var useOllama: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            Text("AI Service Provider")
                .font(DesignSystem.titleMedium)
                .foregroundColor(DesignSystem.textPrimary)
            
            Text("Choose your preferred AI service for document summarization")
                .font(DesignSystem.body)
                .foregroundColor(DesignSystem.textSecondary)
            
            HStack(spacing: DesignSystem.spacingL) {
                ServiceOption(
                    title: "OpenAI",
                    subtitle: "Cloud-based AI service",
                    icon: "cloud.fill",
                    iconColor: DesignSystem.accentGreen,
                    features: ["Reliable JSON output", "Fast processing", "Requires API key", "Online connectivity needed"],
                    isSelected: !useOllama
                ) {
                    useOllama = false
                }
                
                ServiceOption(
                    title: "Ollama",
                    subtitle: "Local AI processing",
                    icon: "desktopcomputer",
                    iconColor: DesignSystem.primaryBlue,
                    features: ["Offline processing", "No API key needed", "Flexible processing modes", "Privacy-focused"],
                    isSelected: useOllama
                ) {
                    useOllama = true
                }
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(DesignSystem.settingsCardBackground)
        .cornerRadius(DesignSystem.cornerRadiusL)
        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
    }
}

struct ServiceOption: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let features: [String]
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                HStack(spacing: DesignSystem.spacingM) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusS)
                                .fill(iconColor.opacity(0.1))
                        )
                    
                    VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                        Text(title)
                            .font(DesignSystem.titleSmall)
                            .foregroundColor(DesignSystem.textPrimary)
                        Text(subtitle)
                            .font(DesignSystem.bodySmall)
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.primaryBlue)
                            .font(.system(size: 20, weight: .medium))
                    }
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: DesignSystem.spacingXS) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.accentGreen)
                            Text(feature)
                                .font(DesignSystem.bodySmall)
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                }
            }
            .padding(DesignSystem.spacingL)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                    .fill(isSelected ? DesignSystem.primaryBlue.opacity(0.1) : (isHovered ? DesignSystem.backgroundSecondary : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                            .stroke(isSelected ? DesignSystem.primaryBlue : DesignSystem.separatorColor, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Ollama Configuration Card
struct OllamaConfigurationCard: View {
    @Binding var apiURL: String
    @Binding var model: String
    @Binding var processingMode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            Text("Ollama Configuration")
                .font(DesignSystem.titleMedium)
                .foregroundColor(DesignSystem.textPrimary)
            
            Text("Configure your local Ollama instance settings")
                .font(DesignSystem.body)
                .foregroundColor(DesignSystem.textSecondary)
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("API URL")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    TextField("Ollama API URL", text: $apiURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(DesignSystem.body)
                    Text("Default: http://localhost:11434/api/chat")
                        .font(DesignSystem.caption)
                        .foregroundColor(DesignSystem.textTertiary)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Model Name")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    TextField("Model name (e.g., llama3.1:8b)", text: $model)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(DesignSystem.body)
                    Text("Make sure the model is installed with: ollama pull \(model)")
                        .font(DesignSystem.caption)
                        .foregroundColor(DesignSystem.textTertiary)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Processing Mode")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Picker("Processing Mode", selection: $processingMode) {
                        Text("🚀 Fast Mode").tag("fast")
                        Text("🎯 Vision Mode").tag("vision")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .background(DesignSystem.backgroundSecondary)
                    .cornerRadius(DesignSystem.cornerRadiusS)
                    
                    ProcessingModeInfo(mode: processingMode)
                }
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(DesignSystem.settingsCardBackground)
        .cornerRadius(DesignSystem.cornerRadiusL)
        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
    }
}

struct ProcessingModeInfo: View {
    let mode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            if mode == "fast" {
                InfoSection(
                    title: "Fast Mode (OCR + Text Model)",
                    workflow: "OCR → Text processing → Comprehensive summary",
                    color: DesignSystem.primaryBlue,
                    benefits: [
                        "⚡ Fast processing speed",
                        "📝 Comprehensive 3-5 sentence summaries",
                        "🔍 Detailed analysis with key findings",
                        "💾 Low resource usage"
                    ],
                    models: [
                        "llama3.1:8b - Fast and reliable",
                        "mistral:7b - Excellent for summaries",
                        "qwen2.5:7b - Good instruction following",
                        "phi3:medium - Very fast processing"
                    ]
                )
            } else {
                InfoSection(
                    title: "Vision Mode (Direct Processing)",
                    workflow: "Direct file processing → Comprehensive summary",
                    color: DesignSystem.accentOrange,
                    benefits: [
                        "👁️ Analyzes visual elements",
                        "📊 Reads charts and tables",
                        "🎯 Handles complex layouts",
                        "⚠️ Slower processing speed"
                    ],
                    models: [
                        "qwen2.5vl:7b - Best overall vision model",
                        "llava:7b/13b - Good image understanding",
                        "minicpm-v:8b - Fast vision processing",
                        "bakLlava:7b - Document specialized"
                    ]
                )
            }
        }
    }
}

struct InfoSection: View {
    let title: String
    let workflow: String
    let color: Color
    let benefits: [String]
    let models: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            Text(title)
                .font(DesignSystem.headline)
                .foregroundColor(color)
            
            Text(workflow)
                .font(DesignSystem.bodySmall)
                .foregroundColor(DesignSystem.textSecondary)
                .padding(.horizontal, DesignSystem.spacingM)
                .padding(.vertical, DesignSystem.spacingS)
                .background(color.opacity(0.1))
                .cornerRadius(DesignSystem.cornerRadiusS)
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                ForEach(benefits, id: \.self) { benefit in
                    Text(benefit)
                        .font(DesignSystem.bodySmall)
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                Text("Recommended Models:")
                    .font(DesignSystem.caption)
                    .foregroundColor(DesignSystem.textSecondary)
                    .fontWeight(.semibold)
                
                ForEach(models, id: \.self) { model in
                    Text("• \(model)")
                        .font(DesignSystem.caption)
                        .foregroundColor(DesignSystem.textTertiary)
                }
            }
        }
        .padding(DesignSystem.spacingM)
        .background(DesignSystem.backgroundSecondary)
        .cornerRadius(DesignSystem.cornerRadiusM)
    }
}

// MARK: - OpenAI Configuration Card
struct OpenAIConfigurationCard: View {
    @Binding var apiKey: String
    @Binding var model: String
    
    private let openAIModels = ["gpt-3.5-turbo", "gpt-4", "gpt-4o"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            Text("OpenAI Configuration")
                .font(DesignSystem.titleMedium)
                .foregroundColor(DesignSystem.textPrimary)
            
            Text("Configure your OpenAI API settings for cloud-based processing")
                .font(DesignSystem.body)
                .foregroundColor(DesignSystem.textSecondary)
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("API Key")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    SecureField("Enter your OpenAI API key", text: $apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(DesignSystem.body)
                    
                    HStack(spacing: DesignSystem.spacingXS) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.accentGreen)
                        Text("Your API key is stored securely on your device")
                            .font(DesignSystem.caption)
                            .foregroundColor(DesignSystem.textTertiary)
                    }
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Model Selection")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Picker("OpenAI Model", selection: $model) {
                        ForEach(openAIModels, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .background(DesignSystem.backgroundSecondary)
                    .cornerRadius(DesignSystem.cornerRadiusS)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Processing Workflow")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.primaryBlue)
                    
                    Text("OCR → Text processing → JSON structured output")
                        .font(DesignSystem.bodySmall)
                        .foregroundColor(DesignSystem.textSecondary)
                        .padding(.horizontal, DesignSystem.spacingM)
                        .padding(.vertical, DesignSystem.spacingS)
                        .background(DesignSystem.primaryBlue.opacity(0.1))
                        .cornerRadius(DesignSystem.cornerRadiusS)
                    
                    Text("✅ Reliable structured output with consistent JSON formatting")
                        .font(DesignSystem.bodySmall)
                        .foregroundColor(DesignSystem.accentGreen)
                }
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(DesignSystem.settingsCardBackground)
        .cornerRadius(DesignSystem.cornerRadiusL)
        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
    }
}

// MARK: - OCR Language Card
struct OCRLanguageCard: View {
    @Binding var selectedLanguage: String
    let languages: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            Text("OCR Language Settings")
                .font(DesignSystem.titleMedium)
                .foregroundColor(DesignSystem.textPrimary)
            
            Text("Select the primary language for optical character recognition")
                .font(DesignSystem.body)
                .foregroundColor(DesignSystem.textSecondary)
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                Text("Language")
                    .font(DesignSystem.headline)
                    .foregroundColor(DesignSystem.textPrimary)
                
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .background(DesignSystem.backgroundSecondary)
                .cornerRadius(DesignSystem.cornerRadiusS)
                
                Text("This setting affects text extraction accuracy for the selected language")
                    .font(DesignSystem.caption)
                    .foregroundColor(DesignSystem.textTertiary)
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(DesignSystem.settingsCardBackground)
        .cornerRadius(DesignSystem.cornerRadiusL)
        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Custom Prompt Card
struct CustomPromptCard: View {
    @Binding var prompt: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
            HStack {
                Text("Custom Summarization Prompt")
                    .font(DesignSystem.titleMedium)
                    .foregroundColor(DesignSystem.textPrimary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(DesignSystem.primaryBlue)
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("Customize the AI prompt to improve summary quality and format")
                .font(DesignSystem.body)
                .foregroundColor(DesignSystem.textSecondary)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                    Text("Current Prompt:")
                        .font(DesignSystem.headline)
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    TextEditor(text: $prompt)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(DesignSystem.spacingM)
                        .background(DesignSystem.backgroundSecondary)
                        .cornerRadius(DesignSystem.cornerRadiusM)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusM)
                                .stroke(DesignSystem.separatorColor, lineWidth: 1)
                        )
                    
                    Button("Reset to Default") {
                        prompt = "You are an expert text analyzer. Read the following text carefully. Provide a clear, concise, and well-structured summary in 3–4 short paragraphs, highlighting the main ideas and important details without repeating phrases or filler words. Your response must be a very details, flat JSON object with only two keys: 'summary' and 'keywords'."
                    }
                    .buttonStyle(MacOSButtonStyle(isSecondary: true))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(DesignSystem.settingsCardBackground)
        .cornerRadius(DesignSystem.cornerRadiusL)
        .shadow(color: DesignSystem.shadowLight, radius: 2, x: 0, y: 1)
    }
}

#Preview {
    SettingsView()
} 
 
