//
//  PlayerView.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

// Créez un fichier PlayerView.swift dans le dossier Player
import SwiftUI
import AVKit

struct PlayerView: View {
    let recording: Recording
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                Text("Unable to load video")
                    .foregroundColor(.red)
            }
            
            HStack {
                Text(recording.mapName)
                    .font(.headline)
                
                Spacer()
                
                Text("Duration: \(formatDuration(recording.duration))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            loadVideo()
        }
    }
    
    private func loadVideo() {
        let fileURL = URL(fileURLWithPath: recording.filePath)
        player = AVPlayer(url: fileURL)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
    }
}
