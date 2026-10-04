//
//  ModelContext+SaveNow.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import OSLog
import SwiftData

extension ModelContext {
    /// Saves pending changes right away. SwiftData's autosave can wait until the app leaves the
    /// foreground, so an edit could be lost if the app quits unexpectedly. Errors are logged.
    func saveNow() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            Logger(subsystem: "com.ajoe.Mint", category: "Persistence")
                .error("Couldn't save changes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
