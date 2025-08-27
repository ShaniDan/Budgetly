//
//  BudgetModel.swift
//  Budgetly
//
//  Created by Shakhnoza Mirabzalova on 8/27/25.
//

import Foundation
import SwiftData

final class Budget {
    
    var name: String
    var limit: Double
    
    init(name: String, limit: Double) {
        self.name = name
        self.limit = limit
    }
}
