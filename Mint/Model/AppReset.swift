//
//  AppReset.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// Erases all entries, repeating series, balance adjustments and settings. Can't be undone.
enum AppReset {
    static func eraseAll(in context: ModelContext, defaults: UserDefaults) {
        let undoManager = context.undoManager
        undoManager?.disableUndoRegistration()
        defer {
            undoManager?.enableUndoRegistration()
            // Earlier Undo steps would refer to erased data.
            undoManager?.removeAllActions()
        }

        func deleteAll<Model: PersistentModel>(_ type: Model.Type) {
            for model in (try? context.fetch(FetchDescriptor<Model>())) ?? [] {
                context.delete(model)
            }
        }
        deleteAll(Entry.self)
        deleteAll(RecurringSeries.self)
        deleteAll(BalanceAdjustment.self)
        context.saveNow()

        for key in SettingsKey.all {
            defaults.removeObject(forKey: key)
        }
    }
}
