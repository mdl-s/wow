//
//  WarcraftRecorderApp.swift
//  WarcraftRecorder
//

import SwiftUI

@main
struct WarcraftRecorderApp: App {
    // Services partagés avec une portée d'application
    @StateObject var gameDetectionService = GameDetectionService()
    @StateObject var recordingService = RecordingService()
    @StateObject var storageService = StorageService()
    
    // Timer pour la détection automatique de WoW
    private let wowCheckTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    init() {
        // Paramètres initiaux au lancement de l'application
        print("WarcraftRecorder starting up")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameDetectionService)
                .environmentObject(recordingService)
                .environmentObject(storageService)
                .onAppear {
                    // Setup des services
                    gameDetectionService.setRecordingService(recordingService)
                    
                    // Vérifier WoW au démarrage
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        checkForWoW()
                    }
                }
                .onReceive(wowCheckTimer) { _ in
                    // Vérification périodique de WoW
                    checkForWoW()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Start Monitoring") {
                    gameDetectionService.startMonitoring()
                }
                .keyboardShortcut("M")
                
                Button("Stop Monitoring") {
                    gameDetectionService.stopMonitoring()
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Start Manual Recording") {
                    _ = recordingService.startRecording(gameType: .clip, mapName: "Manual Recording")
                }
                .keyboardShortcut("R")
                
                Button("Stop Recording") {
                    if let recording = recordingService.stopRecording() {
                        storageService.saveRecording(recording)
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            }
        }
    }
    
    // Fonction pour vérifier si WoW est en cours d'exécution
    private func checkForWoW() {
        // Vérifier si WoW est lancé
        gameDetectionService.checkWoWRunning()
        
        // Si l'auto-monitoring est activé et que WoW est en cours d'exécution mais que le monitoring n'est pas démarré
        if gameDetectionService.autoStartMonitoring &&
           gameDetectionService.wowIsRunning &&
           !gameDetectionService.isMonitoring {
            
            print("WoW detected and auto-monitoring is enabled. Starting monitoring...")
            gameDetectionService.startMonitoring()
            
            // Afficher une notification
            showNotification(title: "WarcraftRecorder", message: "Monitoring started automatically because WoW was detected")
        }
    }
    
    // Fonction pour afficher une notification
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
