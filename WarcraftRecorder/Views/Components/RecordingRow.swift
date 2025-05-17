//
//  RecordingRow.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import SwiftUI

struct RecordingRow: View {
    let recording: Recording
    
    var body: some View {
        HStack {
            Image(systemName: "folder")
            Text(recording.mapName)
            
            Spacer()
            
            Text(recording.result)
                .foregroundColor(recording.result.contains("+") ? .green : .primary)
            
            Text("+\(recording.difficulty)")
                .padding(.horizontal)
            
            Text(formatDuration(recording.duration))
            
            Text(formatDate(recording.date))
        }
        .padding(.vertical, 4)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm d MMM"
        return formatter.string(from: date)
    }
}
