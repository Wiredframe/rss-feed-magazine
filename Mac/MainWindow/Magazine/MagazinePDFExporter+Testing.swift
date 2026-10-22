//
//  MagazinePDFExporter+Testing.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

#if DEBUG

import AppKit
import Account
import Articles

extension MagazinePDFExporter {

	/// For checking the export without the UI: launch a debug build with MAGAZINE_EXPORT_PDF=/path/to/file.pdf.
	/// Exports the newest unread articles of the default account, then quits.
	static func exportForTestingIfRequested() {
		selectForTestingIfRequested()
		guard let path = ProcessInfo.processInfo.environment["MAGAZINE_EXPORT_PDF"] else {
			return
		}
		Task { @MainActor in
			let account = AccountManager.shared.defaultAccount
			let articles = await account.fetchArticlesAsync(.unread())
				.sorted { $0.logicalDatePublished > $1.logicalDatePublished }
			let exporter = MagazinePDFExporter(articles: Array(articles.prefix(60)), title: "All Unread")
			let progress = MagazinePDFExportProgress()
			progress.pageCount = exporter.pageCount
			if let window = NSApplication.shared.windows.first(where: \.isVisible) {
				progress.show(on: window)
			}
			try? await exporter.export(to: URL(fileURLWithPath: path)) { page in
				progress.page = page
			}
			progress.close()
			NSApplication.shared.terminate(nil)
		}
	}

	/// MAGAZINE_SELECT=<folder name or "All Unread"> refreshes all feeds and selects that sidebar item.
	static func selectForTestingIfRequested() {
		guard let name = ProcessInfo.processInfo.environment["MAGAZINE_SELECT"] else {
			return
		}
		AccountManager.shared.refreshAllWithoutWaiting()
		Task { @MainActor in
			try? await Task.sleep(for: .seconds(2))
			guard let windowController = NSApplication.shared.windows.compactMap({ $0.windowController as? MainWindowController }).first else {
				return
			}
			if name == "All Unread" {
				windowController.selectForTesting(SmartFeedsController.shared.unreadFeed)
			} else if let folder = AccountManager.shared.defaultAccount.folders?.first(where: { $0.nameForDisplay == name }) {
				windowController.selectForTesting(folder)
			}
		}
	}
}

#endif
