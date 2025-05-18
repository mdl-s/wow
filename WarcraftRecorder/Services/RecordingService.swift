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
    private var currentRecordingInfo: (gameType: GameType, mapName: String)?
    private var videoURL: URL?
    private var startTime: Date?
    private var timer: Timer?
    private var frameCount: Int64 = 0
    private var isProcessingStop = false
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

        let outputPath = generateFilePath(gameType: gameType, mapName: mapName)
        currentRecordingPath = outputPath
        return outputPath
    }

    func stopRecording() -> Recording? {
        guard isRecording && !isProcessingStop else {
            print("No recording to stop or recording failed to save")
            return nil
        }
        isProcessingStop = true

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

        Task { [weak self] in
            await self?.stopRecordingAsync()
        }

        return recording
    }

    // MARK: - Async workflow
    private func startRecordingAsync(gameType: GameType, mapName: String) async {
        do {
            // 1. Cherche d'abord la fenêtre WoW (window), sinon fallback display
            let captureTarget = await findWoWWindowOrDisplay()
            guard let target = captureTarget else {
                self.recordingError = "Impossible de trouver une fenêtre ou display à capturer."
                print("No WoW window or display found")
                return
            }

            // 2. Chemin de sortie
            let outputPath = currentRecordingPath ?? generateFilePath(gameType: gameType, mapName: mapName)
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            self.videoURL = outputURL
            self.currentRecordingPath = outputPath

            // 3. Taille capture selon la source
            let (width, height): (Int, Int)
            if let window = target as? SCWindow {
                width = max(Int(window.frame.size.width), 640)
                height = max(Int(window.frame.size.height), 480)
            } else if let display = target as? SCDisplay {
                width = max(Int(display.width), 640)
                height = max(Int(display.height), 480)
            } else {
                width = 1280; height = 720
            }

            // 4. Setup AVAssetWriter
            let (writer, writerInput, adaptor) = try setupAVWriter(url: outputURL, width: width, height: height)
            await MainActor.run {
                self.assetWriter = writer
                self.videoInput = writerInput
                self.pixelBufferAdaptor = adaptor
                self.frameCount = 0
            }

            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            // 5. Setup ScreenCaptureKit
            let streamOutput = WarcraftSCStreamOutput { [weak self] pixelBuffer in
                guard let self = self else { return }
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
            config.showsCursor = false
            config.minimumFrameInterval = CMTimeMake(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA

            // 6. Préparation du filtre
            let filter: SCContentFilter
            if let window = target as? SCWindow {
                print("🎯 Capture mode: Window")
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else if let display = target as? SCDisplay {
                print("🎯 Capture mode: Display")
                filter = SCContentFilter(display: display, excludingWindows: []) // <= Correction ici
            } else {
                fatalError("Should never happen: unknown capture target")
            }


            let stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
            self.stream = stream

            let streamOutputQueue = DispatchQueue(label: "com.warcraft.streamOutputQueue", qos: .userInteractive)
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: streamOutputQueue)
            try await stream.startCapture()

            // 7. Mise à jour de l'état
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
                if frameCount % 30 == 0 {
                    print("Frame count: \(frameCount)")
                }
            } else {
                print("Failed to append pixel buffer at \(pts)")
            }
        }
    }

    private func stopRecordingAsync() async {
        print("Stopping recording...")

        if let stream = stream {
            do {
                try await stream.stopCapture()
                print("Stream capture stopped successfully")
            } catch {
                print("Erreur lors de l'arrêt du stream ScreenCaptureKit : \(error)")
            }
        }

        await MainActor.run {
            self.stream = nil
            self.streamOutput = nil
            self.timer?.invalidate()
            self.timer = nil
        }

        await MainActor.run {
            self.videoInput?.markAsFinished()
        }

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
    }

    // MARK: - AVAssetWriter setup
    private func setupAVWriter(url: URL, width: Int, height: Int) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        let validWidth = max(width, 640) & ~1
        let validHeight = max(height, 480) & ~1

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

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

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: validWidth,
            kCVPixelBufferHeightKey as String: validHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        return (writer, input, adaptor)
    }

    // MARK: - Capture target: window OU display
    private func findWoWWindowOrDisplay() async -> AnyObject? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // 1. Essaie fenêtre WoW
            for window in content.windows {
                let appName = window.owningApplication?.applicationName.lowercased() ?? ""
                let title = window.title?.lowercased() ?? ""
                if appName.contains("warcraft") || appName.contains("wow") || title.contains("world of warcraft") || title.contains("wow") {
                    print("🎯 Capture target: window (WoW)")
                    return window
                }
            }

            // 2. Sinon, fallback: premier écran trouvé
            if let display = content.displays.first {
                print("🎯 Fallback to display: \(display.displayID)")
                return display
            }
        } catch {
            print("Error getting window/display for capture: \(error)")
        }
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
