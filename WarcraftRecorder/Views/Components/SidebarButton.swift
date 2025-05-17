//
//  SidebarButton.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import SwiftUI

struct SidebarButton: View {
    let icon: String
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
                if let count = count, count > 0 {
                    Text("\(count)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
