//
//  AppEnvironment.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// Decides where this launch keeps its data.
enum AppEnvironment {
    /// Every SwiftData model Mint stores.
    static let models: [any PersistentModel.Type] = [Entry.self, RecurringSeries.self, BalanceAdjustment.self]

    /// True while the unit tests run inside the app.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Launch with `-demo YES` to try the app with sample data. Nothing is saved.
    static let isDemo = UserDefaults.standard.bool(forKey: "demo")

    /// Tests and demo mode keep everything in memory so real data is never touched.
    static var usesTemporaryData: Bool { isRunningTests || isDemo }

    /// Where settings such as the statistics period live. Tests and demo mode get a separate suite
    /// that's emptied each launch.
    static let defaults: UserDefaults = {
        let scratchName = "com.ajoe.Mint.scratch"
        guard usesTemporaryData, let scratch = UserDefaults(suiteName: scratchName) else { return .standard }
        scratch.removePersistentDomain(forName: scratchName)
        return scratch
    }()
}
