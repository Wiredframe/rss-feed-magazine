//
//  MagazinePDFExportProgress.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import SwiftUI

/// A sheet that shows the PDF export’s progress and can cancel it.
@MainActor final class MagazinePDFExportProgress: ObservableObject {

	@Published var page = 0
	@Published var pageCount = 0
	var cancel: (() -> Void)?

	private var sheet: NSWindow?
	private var isClosed = false // A short export can finish before the sheet is shown

	func show(on window: NSWindow) {
		guard !isClosed else {
			return
		}
		let sheet = NSWindow(contentViewController: NSHostingController(rootView: MagazinePDFExportProgressView(progress: self)))
		sheet.styleMask = [.titled]
		self.sheet = sheet
		window.beginSheet(sheet)
	}

	func close() {
		isClosed = true
		guard let sheet else {
			return
		}
		sheet.sheetParent?.endSheet(sheet)
		self.sheet = nil
	}
}

private struct MagazinePDFExportProgressView: View {

	@ObservedObject var progress: MagazinePDFExportProgress

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Exporting Magazine as PDF", comment: "PDF export progress: title")
				.font(.headline)
			ProgressView(value: Double(progress.page), total: Double(max(progress.pageCount, 1)))
			HStack {
				Text(String(format: NSLocalizedString("Page %d of %d", comment: "PDF export progress"), progress.page, progress.pageCount))
					.foregroundStyle(.secondary)
					.monospacedDigit()
				Spacer()
				Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
					progress.cancel?()
				}
				.keyboardShortcut(.cancelAction)
			}
		}
		.padding(20)
		.frame(width: 360)
	}
}
