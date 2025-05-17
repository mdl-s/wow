import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct GeneralSettingsView: View {
    @EnvironmentObject var gameDetectionService: GameDetectionService
    @EnvironmentObject var recordingService: RecordingService
    
    @State private var logFolderPath: String = ""
    @State private var recordingsFolder: String = ""
    @State private var autoStartRecording: Bool = true
    @State private var autoStartMonitoring: Bool = false
    @State private var selectedQuality: String = "High"
    @State private var status: String = ""
    
    private let videoQualities = ["Low", "Medium", "High", "Ultra"]
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Detection Settings")
                    .font(.headline)
                    .padding(.bottom, 5)
                ) {
                    HStack {
                        Text("WoW Logs Folder:")
                        TextField("Path to Logs folder", text: $logFolderPath)
                            .disabled(true)
                        Button("Browse...") {
                            selectLogFolder()
                        }
                    }
                    .padding(.vertical, 2)
                    
                    Button("Auto-Detect Logs Folder") {
                        autoDetectLogFolder()
                    }
                    .padding(.vertical, 2)
                    
                    Toggle("Auto-start recording when game detected", isOn: $autoStartRecording)
                        .padding(.vertical, 2)
                        .help("Automatically start recording when arena, dungeon, or raid is detected")
                    
                    Toggle("Auto-start monitoring when WoW is detected", isOn: $autoStartMonitoring)
                        .padding(.vertical, 2)
                        .help("Automatically start monitoring when World of Warcraft is launched")
                    
                    Text("When enabled, monitoring will start automatically as soon as WoW is detected running on your system.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.bottom, 10)
                
                Section(header: Text("Recording Settings")
                    .font(.headline)
                    .padding(.bottom, 5)
                ) {
                    HStack {
                        Text("Recordings Folder:")
                        TextField("Path to recordings folder", text: $recordingsFolder)
                            .disabled(true)
                        Button("Browse...") {
                            selectRecordingsFolder()
                        }
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading) {
                        Text("Video Quality")
                            .padding(.vertical, 2)
                        
                        Picker("Video Quality", selection: $selectedQuality) {
                            ForEach(videoQualities, id: \.self) { quality in
                                Text(quality)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        qualityDescription
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 10)
                
                Section(header: Text("Notifications")
                    .font(.headline)
                    .padding(.bottom, 5)
                ) {
                    Toggle("Show notifications when recording starts/stops", isOn: .constant(true))
                        .padding(.vertical, 2)
                    
                    Toggle("Show notification when WoW is detected", isOn: .constant(true))
                        .padding(.vertical, 2)
                }
                .padding(.bottom, 10)
                
                if !status.isEmpty {
                    Text(status)
                        .foregroundColor(status.contains("Error") ? .red : .green)
                        .padding()
                }
                
                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: 200)
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
                .padding(.vertical, 10)
            }
            .padding()
            
            // Instructions
            VStack(alignment: .leading, spacing: 10) {
                Text("How to enable WoW Combat Logging:")
                    .font(.headline)
                
                Text("1. In WoW, open the main menu and click on 'System'")
                Text("2. Click on the 'Network' tab")
                Text("3. Check the box for 'Advanced Combat Logging'")
                Text("4. Enter the command '/combatlog' in the game chat to start logging")
                
                Text("Common log folder locations:")
                    .font(.headline)
                    .padding(.top, 5)
                
                Text("• Retail: World of Warcraft/_retail_/Logs")
                Text("• Classic: World of Warcraft/_classic_/Logs")
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .padding()
        }
        .onAppear {
            loadSettings()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Description dynamique de la qualité sélectionnée
    private var qualityDescription: some View {
        let description: String
        switch selectedQuality {
        case "Low":
            description = "1280x720 at 30 FPS (5 Mbps) - Lower file size, suitable for sharing"
        case "Medium":
            description = "1920x1080 at 60 FPS (8 Mbps) - Balanced quality and file size"
        case "High":
            description = "2560x1440 at 60 FPS (15 Mbps) - Higher quality for detailed footage"
        case "Ultra":
            description = "3840x2160 at 60 FPS (30 Mbps) - Maximum quality, large file size"
        default:
            description = ""
        }
        
        return Text(description)
    }
    
    private func loadSettings() {
        logFolderPath = gameDetectionService.logFolderPath
        recordingsFolder = recordingService.recordingsFolder
        
        // Charger la qualité vidéo actuelle si déjà sauvegardée (sinon garder la valeur par défaut)
        if let storedQuality = UserDefaults.standard.string(forKey: "videoQuality") {
            selectedQuality = storedQuality
        }
        
        autoStartMonitoring = gameDetectionService.autoStartMonitoring
        // AutoStartRecording n’est qu’en local ici, à adapter à ton architecture si tu veux l’utiliser dans le service
        
        if logFolderPath.isEmpty {
            autoDetectLogFolder()
        }
    }
    
    private func saveSettings() {
        gameDetectionService.logFolderPath = logFolderPath
        recordingService.recordingsFolder = recordingsFolder
        
        // Sauvegarder dans UserDefaults pour retrouver la sélection
        UserDefaults.standard.set(selectedQuality, forKey: "videoQuality")
        
        // Mémoriser autoStartMonitoring (à utiliser dans GameDetectionService pour l’automatisme)
        gameDetectionService.autoStartMonitoring = autoStartMonitoring
        
        status = "Settings saved successfully!"
        
        // Si le monitoring est actif, redémarrer pour prendre en compte les nouveaux paramètres
        if gameDetectionService.isMonitoring {
            gameDetectionService.stopMonitoring()
            gameDetectionService.startMonitoring()
        }
    }
    
    private func autoDetectLogFolder() {
        status = "Searching for WoW logs folder..."
        gameDetectionService.findWoWLogFolder()
        
        // Mettre à jour le chemin dans l'interface
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            logFolderPath = gameDetectionService.logFolderPath
            if !logFolderPath.isEmpty {
                status = "Found logs folder: \(logFolderPath)"
            } else {
                status = "Error: Could not find logs folder. Please select it manually."
            }
        }
    }
    
    private func selectLogFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select WoW Logs Folder"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    self.logFolderPath = url.path
                    self.status = "Selected logs folder: \(url.lastPathComponent)"
                }
            }
        }
    }
    
    private func selectRecordingsFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Recordings Folder"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    self.recordingsFolder = url.path
                    self.status = "Selected recordings folder: \(url.lastPathComponent)"
                }
            }
        }
    }
}

// Pour le preview Xcode
#Preview {
    GeneralSettingsView()
        .environmentObject(GameDetectionService())
        .environmentObject(RecordingService())
}
