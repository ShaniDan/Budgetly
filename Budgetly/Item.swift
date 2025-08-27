//
//  Item.swift
//  Budgetly
//
//  Created by Shakhnoza Mirabzalova on 8/27/25.
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
