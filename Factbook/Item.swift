//
//  Item.swift
//  Factbook
//
//  Created by Srivatsav Karamala on 4/4/26.
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
