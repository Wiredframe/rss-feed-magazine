//
//  AppRenameMigration.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/23/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import Foundation

/// The fork was called NetNewsFeed before it became RSS Feed Magazine. Its data folder is named after the app,
/// so the subscriptions, articles, and their read and starred states move over once, before anything reads them.
enum AppRenameMigration {

	/// After a move the app’s defaults are new, so it would take this for a first run and add the default feeds.
	nonisolated(unsafe) private(set) static var didMoveDataFolder = false // Set once at launch, on the main thread

	static func moveDataFolderIfNeeded() {
		let fileManager = FileManager.default
		guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
			  let appName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String else {
			return
		}
		let newFolder = applicationSupport.appendingPathComponent(appName, isDirectory: true)
		let oldFolder = applicationSupport.appendingPathComponent("NetNewsFeed", isDirectory: true)
		guard !fileManager.fileExists(atPath: newFolder.path), fileManager.fileExists(atPath: oldFolder.path) else {
			return
		}
		do {
			try fileManager.moveItem(at: oldFolder, to: newFolder)
			didMoveDataFolder = true
		} catch {
			return
		}

		// The magazine’s reading positions were stored under the old bundle ID.
		if let positions = UserDefaults(suiteName: "de.wiredframe.NetNewsFeed")?.dictionary(forKey: "magazineReadingPositions") {
			UserDefaults.standard.set(positions, forKey: "magazineReadingPositions")
		}
	}
}
