//
//  Item.swift
//  WarcraftRecorder
//
//  Created by michael slimani on 12/05/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
