//
//  MagazineSections.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import SwiftUI
import Account
import Articles

/// Each folder is a section of the magazine with its own color. An article carries its folder’s color
/// wherever it appears, so a combined view like All Unread shows at a glance when the section changes.
/// Colors aren’t stored: they follow from the folder names, the same every time.
@MainActor struct MagazineSections {

	private var sectionByFeed = [String: String]() // "accountID feedID": folder name
	private var colorBySection = [String: Color]()

	init(accounts: [Account]) {
		var sectionNames = Set<String>()
		for account in accounts {
			for folder in account.folders ?? [] {
				let name = folder.nameForDisplay
				sectionNames.insert(name)
				for feed in folder.topLevelFeeds {
					sectionByFeed[Self.key(account.accountID, feed.feedID)] = name
				}
			}
		}
		colorBySection = Self.colors(for: sectionNames)
	}

	func section(for article: Article) -> String? {
		sectionByFeed[Self.key(article.accountID, article.feedID)]
	}

	/// Feeds outside any folder get a neutral color.
	func color(forSection section: String?) -> Color {
		guard let section, let color = colorBySection[section] else {
			return Color(nsColor: .secondaryLabelColor)
		}
		return color
	}
}

private extension MagazineSections {

	static func key(_ accountID: String, _ feedID: String) -> String {
		accountID + " " + feedID
	}

	/// Each section starts at the color its name hashes to and takes the next free one,
	/// so no two sections share a color while there are colors left.
	static func colors(for sectionNames: Set<String>) -> [String: Color] {
		var result = [String: Color]()
		var usedIndexes = Set<Int>()
		for name in sectionNames.sorted() {
			var index = stableHash(name) % palette.count
			if usedIndexes.count < palette.count {
				while usedIndexes.contains(index) {
					index = (index + 1) % palette.count
				}
			}
			usedIndexes.insert(index)
			result[name] = palette[index]
		}
		return result
	}

	/// Swift’s hashValue changes between launches; colors shouldn’t.
	static func stableHash(_ s: String) -> Int {
		s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
	}

	/// Dark enough for small text on white, with lighter versions for the black page and dark mode.
	static let palette: [Color] = [
		color(light: 0xB4232C, dark: 0xFF6B6B), // Red
		color(light: 0x1F4FB8, dark: 0x6E9BFF), // Blue
		color(light: 0xC2410C, dark: 0xFF8A4C), // Orange
		color(light: 0x0F766E, dark: 0x3CC7B6), // Teal
		color(light: 0x6D28D9, dark: 0xA98BFF), // Violet
		color(light: 0x2F7D1F, dark: 0x6FCF5A), // Green
		color(light: 0xBE185D, dark: 0xFF6FA8), // Raspberry
		color(light: 0x9A6700, dark: 0xE3B341), // Ochre
		color(light: 0x3F5873, dark: 0x93A9C4), // Slate
		color(light: 0x8A4B2A, dark: 0xD29A72)  // Brown
	]

	static func color(light: Int, dark: Int) -> Color {
		Color(nsColor: NSColor(name: nil) { appearance in
			let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			return rgb(isDark ? dark : light)
		})
	}

	nonisolated static func rgb(_ hex: Int) -> NSColor {
		NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
	}
}
