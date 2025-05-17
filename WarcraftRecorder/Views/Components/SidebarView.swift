//
//  SidebarView.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//
import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: GameType?
    @Binding var status: String
    @Binding var showSettings: Bool
    let recordings: [Recording]
    
    @EnvironmentObject var gameDetectionService: GameDetectionService
    
    var body: some View {
        VStack {
            // Status amélioré
            VStack(alignment: .leading) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(status)
                    .font(.headline)
                    .foregroundColor(statusColor)
                    .padding(.bottom, 5)
                
                // Section du statut de l'application
                if gameDetectionService.isMonitoring {
                    Label("Monitoring Active", systemImage: "eye")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Monitoring Inactive", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                // Statut de WoW
                if gameDetectionService.wowIsRunning {
                    Label("WoW Running", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("WoW Not Running", systemImage: "x.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Application Status détaillé
            Section(header: Text("Application Status")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            ) {
                // Status de WoW
                HStack {
                    Image(systemName: gameDetectionService.wowIsRunning ? "checkmark.circle.fill" : "x.circle")
                        .foregroundColor(gameDetectionService.wowIsRunning ? .green : .red)
                    Text("World of Warcraft")
                    Spacer()
                    Text(gameDetectionService.wowIsRunning ? "Running" : "Not detected")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                
                // Status du monitoring
                HStack {
                    Image(systemName: gameDetectionService.isMonitoring ? "eye" : "eye.slash")
                        .foregroundColor(gameDetectionService.isMonitoring ? .green : .orange)
                    Text("Log Monitoring")
                    Spacer()
                    Text(gameDetectionService.isMonitoring ? "Active" : "Inactive")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                
                // Status des logs
                if gameDetectionService.logFilesFound {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.green)
                        Text("Log Files")
                        Spacer()
                        Text("Found")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                } else {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.orange)
                        Text("Log Files")
                        Spacer()
                        Text("Searching...")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(Color(.windowBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 5)
            
            // Categories
            Text("Recordings")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 10)
            
            ForEach(GameType.allCases, id: \.self) { type in
                Button(action: {
                    selectedCategory = type
                    showSettings = false
                }) {
                    HStack {
                        Image(systemName: iconForType(type))
                            .frame(width: 20)
                        Text(type.rawValue)
                        Spacer()
                        Text("\(countForType(type))")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(countForType(type) > 0 ? Color.orange : Color.clear)
                            .foregroundColor(countForType(type) > 0 ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(selectedCategory == type ? Color.blue.opacity(0.2) : Color.clear)
                    .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
            
            // Settings
            Text("Settings")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            Button(action: {
                showSettings = true
                selectedCategory = nil
            }) {
                HStack {
                    Image(systemName: "gear")
                        .frame(width: 20)
                    Text("General")
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(showSettings ? Color.blue.opacity(0.2) : Color.clear)
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                // Action pour Scene settings
            }) {
                HStack {
                    Image(systemName: "tv")
                        .frame(width: 20)
                    Text("Scene")
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 200)
        .background(Color(.windowBackgroundColor))
    }
    
    var statusColor: Color {
        if status.contains("Recording") {
            return .red
        } else if status.contains("Monitoring") || status.contains("Detected") {
            return .green
        } else if status == "Waiting" || status.contains("not") {
            return .orange
        } else {
            return .primary
        }
    }
    
    func iconForType(_ type: GameType) -> String {
        switch type {
        case .arena2v2, .arena3v3, .arena5v5:
            return "person.2"
        case .skirmish:
            return "shield"
        case .soloShuffle:
            return "shuffle"
        case .mythicPlus:
            return "star"
        case .raid:
            return "person.3"
        case .battleground:
            return "flag"
        case .clip:
            return "scissors"
        }
    }
    
    func countForType(_ type: GameType) -> Int {
        return recordings.filter { $0.type == type }.count
    }
}
