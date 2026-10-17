//
//  Item.swift
//  rep150
//
//  Created by Oliver Larsson on 10/16/26.
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
