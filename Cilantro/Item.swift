//
//  Item.swift
//  Cilantro
//
//  Created by Andy Joe on 10/2/26.
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
