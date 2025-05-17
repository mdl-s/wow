import SwiftUI
import Combine
import AVFoundation
import ScreenCaptureKit

@MainActor
class RecordingService: ObservableObject {
    // MARK: - Observable State
    @Published var isRecording = false
    @Published var currentRecordingPath: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingStatus: String = "Ready"
    @Published var recordingError: String?
    @Published var recordingsFolder: String
    
    // MARK: - Private State
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var stream: SCStream?
    private var streamOutput: WarcraftSCStreamOutput?
    private var woWWindow: SCWindow?
    private var currentRecordingInfo: (gameType: GameType, mapName: String)?
    private var videoURL: URL?
    private var startTime: Date?
    private var timer: Timer?
    private var frameCount: Int64 = 0
    private var isProcessingStop = false // Garde-fou pour éviter les arrêts multiples
    private var captureQueue = DispatchQueue(label: "com.warcraft.captureQueue", qos: .userInteractive)
    
    // MARK: - Init
    init(recordingsFolder: String? = nil) {
        if let folder = recordingsFolder {
            self.recordingsFolder = folder
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let warcraftRecorderPath = documentsPath.appendingPathComponent("Warcraft Recorder")
            if !FileManager.default.fileExists(atPath: warcraftRecorderPath.path) {
                try? FileManager.default.createDirectory(at: warcraftRecorderPath, withIntermediateDirectories: true)
            }
            self.recordingsFolder = warcraftRecorderPath.path
        }
        print("RecordingService initialized with recordings folder: \(self.recordingsFolder)")
    }
    
    // MARK: - API
    func startRecording(gameType: GameType, mapName: String) -> String? {
        guard !isRecording else {
            print("❌ Failed to start recording for \(gameType.rawValue) - \(mapName)")
            return nil
        }
        
        Task { [weak self] in
            await self?.startRecordingAsync(gameType: gameType, mapName: mapName)
        }
        
        // Générer le chemin tout de suite
        let outputPath = generateFilePath(gameType: gameType, mapName: mapName)
        currentRecordingPath = outputPath
        return outputPath
    }
    
    func stopRecording() -> Recording? {
        // Éviter les appels multiples à stopRecording
        guard isRecording && !isProcessingStop else {
            print("No recording to stop or recording failed to save")
            return nil
        }
        
        isProcessingStop = true
        
        // Créer un objet Recording à retourner
        let recording: Recording?
        if let startTime = startTime, let info = currentRecordingInfo, let path = currentRecordingPath {
            let duration = Date().timeIntervalSince(startTime)
            recording = Recording(
                type: info.gameType,
                mapName: info.mapName,
                date: startTime,
                duration: duration,
                filePath: path,
                result: "Completed",
                difficulty: info.gameType == .mythicPlus ? 10 : 0,
                players: []
            )
        } else {
            recording = nil
        }
        
        // Lancer l'arrêt asynchrone
        Task { [weak self] in
            await self?.stopRecordingAsync()
        }
        
        return recording
    }
    
    // MARK: - Async workflow
    private func startRecordingAsync(gameType: GameType, mapName: String) async {
        do {
            // 1. Find WoW Window
            guard let scWindow = await findWoWWindow() else {
                self.recordingError = "Impossible de trouver la fenêtre World of Warcraft."
                print("WoW window not found")
                return
            }
            self.woWWindow = scWindow
            
            // 2. Output path
            let outputPath = currentRecordingPath ?? generateFilePath(gameType: gameType, mapName: mapName)
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            self.videoURL = outputURL
            self.currentRecordingPath = outputPath
            
            // 3. Setup AVAssetWriter
            let width = max(Int(scWindow.frame.size.width), 640) // Assurer une taille minimale
            let height = max(Int(scWindow.frame.size.height), 480)
            
            let (writer, writerInput, adaptor) = try setupAVWriter(url: outputURL, width: width, height: height)
            await MainActor.run {
                self.assetWriter = writer
                self.videoInput = writerInput
                self.pixelBufferAdaptor = adaptor
                self.frameCount = 0
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            // 4. Setup ScreenCaptureKit
            let streamOutput = WarcraftSCStreamOutput { [weak self] pixelBuffer in
                guard let self = self else { return }
                
                // Utiliser une file d'attente dédiée pour les opérations vidéo
                self.captureQueue.async {
                    Task { @MainActor in
                        self.processPixelBuffer(pixelBuffer)
                    }
                }
            }
            self.streamOutput = streamOutput
            
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.showsCursor = true // Mieux pour débogage
            config.minimumFrameInterval = CMTimeMake(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
            self.stream = stream
            
            // Ajouter une sortie au stream
            let streamOutputQueue = DispatchQueue(label: "com.warcraft.streamOutputQueue", qos: .userInteractive)
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: streamOutputQueue)
            
            try await stream.startCapture()
            
            // 5. Mise à jour de l'état
            await MainActor.run {
                self.isRecording = true
                self.startTime = Date()
                self.currentRecordingInfo = (gameType, mapName)
                self.recordingStatus = "Recording..."
                self.startDurationTimer()
                self.isProcessingStop = false
            }
            
            print("✅ Recording started for \(gameType.rawValue) / \(mapName) (\(outputPath))")
            
        } catch {
            await MainActor.run {
                self.recordingError = "Erreur lors du démarrage : \(error.localizedDescription)"
                self.isRecording = false
            }
            print("ScreenCaptureKit error: \(error)")
        }
    }
    
    @MainActor
    private func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording,
              let writer = assetWriter,
              let input = videoInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData else { return }
        
        let pts = CMTimeMake(value: frameCount, timescale: 30)
        if writer.status == .writing {
            if adaptor.append(pixelBuffer, withPresentationTime: pts) {
                frameCount += 1
                if frameCount % 30 == 0 { // Log toutes les secondes
                    print("Frame count: \(frameCount)")
                }
            } else {
                print("Failed to append pixel buffer at \(pts)")
            }
        }
    }
    
    private func stopRecordingAsync() async {
        print("Stopping recording...")
        
        // 1. Arrêt du stream ScreenCaptureKit
        if let stream = stream {
            do {
                try await stream.stopCapture()
                print("Stream capture stopped successfully")
            } catch {
                print("Erreur lors de l'arrêt du stream ScreenCaptureKit : \(error)")
            }
        }
        
        // 2. Nettoyage des références
        await MainActor.run {
            self.stream = nil
            self.streamOutput = nil
            self.timer?.invalidate()
            self.timer = nil
        }
        
        // 3. Finalisation de l'asset writer
        await MainActor.run {
            self.videoInput?.markAsFinished()
        }
        
        // 4. Finaliser l'écriture du fichier vidéo si l'asset writer est actif
        await MainActor.run {
            guard let assetWriter = self.assetWriter, assetWriter.status == .writing else {
                self.cleanupAfterRecording()
                return
            }
            
            assetWriter.finishWriting { [weak self] in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let videoPath = self.videoURL?.path {
                        print("Recording finalized: \(videoPath)")
                    }
                    self.cleanupAfterRecording()
                }
            }
        }
    }
    
    @MainActor
    private func cleanupAfterRecording() {
        self.isRecording = false
        self.isProcessingStop = false
        self.recordingStatus = "Ready"
        self.recordingDuration = 0
        self.assetWriter = nil
        self.videoInput = nil
        self.pixelBufferAdaptor = nil
        self.startTime = nil
        self.woWWindow = nil
    }
    
    // MARK: - AVAssetWriter setup
    private func setupAVWriter(url: URL, width: Int, height: Int) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        // Assurer des dimensions valides
        let validWidth = max(width, 640) & ~1 // Largeur paire
        let validHeight = max(height, 480) & ~1 // Hauteur paire
        
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        
        // Réglages vidéo
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: validWidth,
            AVVideoHeightKey: validHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        
        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw NSError(domain: "com.warcraftrecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to asset writer"])
        }
        
        // Configuration du pixel buffer adapter
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: validWidth,
            kCVPixelBufferHeightKey as String: validHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        return (writer, input, adaptor)
    }
    
    // MARK: - Window Finder
    private func findWoWWindow() async -> SCWindow? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // D'abord chercher par nom d'application
            for window in content.windows {
                // Correction ici - applicationName n'est pas optionnel
                let appName = window.owningApplication?.applicationName.lowercased() ?? ""
                let title = window.title?.lowercased() ?? ""
                print("Window title: \(title) - app: \(appName)")
                
                if appName.contains("warcraft") || appName.contains("wow") {
                    print("Detected WoW window by application: \(appName)")
                    return window
                }
            }
            
            // Puis par titre de fenêtre
            for window in content.windows {
                let title = window.title?.lowercased() ?? ""
                if title.contains("world of warcraft") || title.contains("wow") || title == "wow" {
                    print("Detected WoW window by title: \(title)")
                    return window
                }
            }
        } catch {
            print("Error getting windows: \(error)")
        }
        
        print("World of Warcraft window not found")
        return nil
    }
    
    // MARK: - Timer
    private func startDurationTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    // MARK: - File Naming
    private func generateFilePath(gameType: GameType, mapName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedMapName = mapName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "_")
        let filename = "\(gameType.rawValue)_\(sanitizedMapName)_\(timestamp).mov"
        return "\(recordingsFolder)/\(filename)"
    }
}

// MARK: - ScreenCaptureKit Output
final class WarcraftSCStreamOutput: NSObject, SCStreamDelegate, SCStreamOutput {
    private let onSampleBufferHandler: (CVPixelBuffer) -> Void
    private var frameCount = 0
    
    init(_ onSampleBuffer: @escaping (CVPixelBuffer) -> Void) {
        self.onSampleBufferHandler = onSampleBuffer
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        frameCount += 1
        onSampleBufferHandler(pixelBuffer)
    }
}
