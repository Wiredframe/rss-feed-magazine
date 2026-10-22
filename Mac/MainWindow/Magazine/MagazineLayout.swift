//
//  MagazineLayout.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import Foundation
import SwiftUI
import RSCore
import Account
import RSParser
import Articles

/// An article as the magazine needs it: plain text, image, and the numbers that decide where it goes.
struct MagazineItem: Identifiable {

	let article: Article
	let title: String
	let text: String
	let imageURL: String?
	let feedName: String
	let accent: Color // The color of the article’s section (folder)

	var id: String {
		article.articleID
	}

	var hasImage: Bool {
		imageURL != nil
	}

	@MainActor init(article: Article, sections: MagazineSections) {
		self.article = article
		let title = ArticleStringFormatter.shared.truncatedTitle(article)
		let html = Self.paragraphs(in: article.contentHTML ?? article.contentText ?? article.summary ?? "")
		// Some feeds encode entities twice (&amp;uuml;), so decode twice.
		var text = String(html.prefix(Self.maxHTMLLength)).strippingHTML(maxCharacters: Self.maxTextLength).decodingHTMLEntities().decodingHTMLEntities()
		if !title.isEmpty && text.hasPrefix(title) {
			text = String(text.dropFirst(title.count)).trimmingCharacters(in: .whitespaces)
		}
		self.title = title.isEmpty ? String(text.prefix(80)) : title
		self.text = Self.removingBoilerplate(text)
		self.imageURL = TimelineImageFinder.shared.imageURL(for: article)
		self.feedName = article.feed?.nameForDisplay ?? ""
		self.accent = sections.color(forSection: sections.section(for: article))
	}

	private static let maxHTMLLength = 12_000
	private static let paragraphPattern = try? NSRegularExpression(pattern: "<p[\\s>].*?</p>", options: [.caseInsensitive, .dotMatchesLineSeparators])

	/// Some feeds (NASA, for one) send the whole web page, menus and all. The paragraphs are the article.
	/// HTML without paragraphs, or plain text, stays as it is.
	private static func paragraphs(in html: String) -> String {
		guard html.count > 2_000, let pattern = paragraphPattern else {
			return html
		}
		let range = NSRange(html.startIndex..., in: html)
		let paragraphs = pattern.matches(in: html, range: range).compactMap { Range($0.range, in: html).map { String(html[$0]) } }
		let text = paragraphs.joined(separator: " ")
		return text.count > 200 ? text : html
	}
	private static let maxTextLength = 2_400

	/// Feeds append things like “The post … appeared first on …” or links to their social accounts.
	private static let boilerplateMarkers = [" Zum Beitrag:", " Weiterlesen", " Read more", " Continue reading", " The post ", " Wo du uns folgen kannst", " Read the full story"]

	private static func removingBoilerplate(_ text: String) -> String {
		var result = text
		for marker in boilerplateMarkers {
			if let range = result.range(of: marker) {
				result = String(result[..<range.lowerBound])
			}
		}
		// URLs can’t be clicked here and can’t be broken nicely; justification would spread them letter by letter.
		result = result.replacingOccurrences(of: #"\s*https?://\S+"#, with: "", options: .regularExpression)
		// Image archives like NASA’s Photojournal start with download links: "JPEG (28.30 MB) PNG (2.12 MB) …"
		result = result.replacingOccurrences(of: #"^(\s*(JPEG|JPG|PNG|TIFF|GIF|PDF)\s*\([\d.,]+\s*[KMG]B\))+\s*"#, with: "", options: .regularExpression)
		// Link aggregators like Hacker News send only labels around those URLs.
		result = result.replacingOccurrences(of: #"(Article URL:|Comments URL:|Points:\s*\d+|#?\s*Comments:\s*\d+)"#, with: "", options: .regularExpression)
		for suffix in ["[…]", "[...]", "(…)"] where result.hasSuffix(suffix) {
			result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) + " …"
		}
		result = result.trimmingCharacters(in: .whitespaces)
		// Feeds that cut their teaser mid-sentence: show that it goes on.
		if let last = result.last, last.isLetter || last.isNumber || last == "," {
			result += " …"
		}
		// A teaser of just "-", "…", or a leftover link label is no teaser.
		if !result.contains(where: { $0.isLetter || $0.isNumber }) || result.trimmingCharacters(in: CharacterSet(charactersIn: " .…#")).lowercased() == "comments" {
			return ""
		}
		return result
	}
}

/// Where a module sits in a block’s 6 × 12 grid. Rows and columns are 1-based, ends are exclusive, as in CSS Grid.
struct MagazineArea: Equatable {
	let row: Int
	let column: Int
	let rowEnd: Int
	let columnEnd: Int

	init(_ row: Int, _ column: Int, _ rowEnd: Int, _ columnEnd: Int) {
		self.row = row
		self.column = column
		self.rowEnd = rowEnd
		self.columnEnd = columnEnd
	}
}

enum MagazineModuleStyle {
	case hero       // Big image, display headline, text in columns with a drop cap
	case feature    // Image on top, headline, text
	case side       // Image on the left half, text on the right
	case lead       // No image, display headline, text in three columns
	case story      // Huge headline and text, next to a full-height photo of the same article
	case darkStory  // Like story, white on black
	case photo      // Full-height image only
}

enum MagazineSlot {
	case masthead
	case module(style: MagazineModuleStyle, area: MagazineArea, item: MagazineItem, imageFraction: CGFloat, columns: Int, dropCap: Bool)
	case briefs(area: MagazineArea, items: [MagazineItem], columns: Int, title: String?)
}

/// One stretch of the magazine, as tall as the view and a fixed number of grid columns wide.
struct MagazineBlock: Identifiable {
	let id: String // Made of its articles, so SwiftUI doesn’t reuse a block’s views for other articles
	let isDark: Bool
	let slots: [MagazineSlot]
}

/// Distributes articles over blocks. Articles stay roughly in order; each slot takes the best fit
/// among the next few articles: images go where images show, long text where text shows.
@MainActor struct MagazineLayout {

	fileprivate enum Kind {
		case photo  // Image and enough text for the story next to it
		case hero   // Image and some text
		case image
		case long
		case longWithImage // The black page: the image fills it, faintly, behind the text
		case brief  // Prefers articles without an image, so images go to slots that show them

		var priority: Int {
			switch self {
			case .photo, .hero: 0
			case .image: 1
			case .long, .longWithImage: 2
			case .brief: 3
			}
		}

		func matches(_ item: MagazineItem) -> Bool {
			switch self {
			case .photo: item.hasImage && item.text.count >= 350
			case .hero: item.hasImage && item.text.count >= 150
			case .image: item.hasImage
			case .long: item.text.count >= 400
			case .longWithImage: item.hasImage && item.text.count >= 400
			case .brief: !item.hasImage
			}
		}
	}

	fileprivate enum SlotSpec {
		case masthead
		case module(MagazineModuleStyle, MagazineArea, Kind, imageFraction: CGFloat = 0, columns: Int = 1, dropCap: Bool = false)
		case storyOfPhoto(MagazineModuleStyle, MagazineArea, columns: Int, dropCap: Bool)
		case briefs(MagazineArea, count: Int, columns: Int, title: String? = nil)

		var kind: Kind {
			switch self {
			case .module(_, _, let kind, _, _, _): kind
			case .briefs: .brief
			case .masthead, .storyOfPhoto: .brief
			}
		}
	}

	fileprivate struct BlockSpec {
		var isDark = false
		let slots: [SlotSpec]
	}

	fileprivate enum Group {
		case opener, newspaper, photo, dark, text

		var blocks: [BlockSpec] {
			switch self {
			case .opener:
				[BlockSpec(slots: [.masthead, .module(.hero, MagazineArea(3, 1, 13, 7), .hero, imageFraction: 0.52, columns: 2, dropCap: true)]),
				 BlockSpec(slots: [.module(.side, MagazineArea(1, 1, 7, 7), .image),
								   .module(.feature, MagazineArea(7, 1, 13, 4), .image, imageFraction: 0.46),
								   .module(.feature, MagazineArea(7, 4, 13, 7), .image, imageFraction: 0.46)])]
			case .newspaper:
				[BlockSpec(slots: [.module(.side, MagazineArea(1, 1, 6, 7), .image),
								   .module(.feature, MagazineArea(6, 1, 13, 4), .image, imageFraction: 0.42),
								   .module(.feature, MagazineArea(6, 4, 13, 7), .image, imageFraction: 0.42)]),
				 BlockSpec(slots: [.module(.lead, MagazineArea(1, 1, 8, 7), .long, columns: 2, dropCap: true),
								   .briefs(MagazineArea(8, 1, 13, 7), count: 4, columns: 2)])]
			case .photo:
				[BlockSpec(slots: [.module(.photo, MagazineArea(1, 1, 13, 7), .photo)]),
				 BlockSpec(slots: [.storyOfPhoto(.story, MagazineArea(1, 1, 9, 7), columns: 2, dropCap: true),
								   .module(.side, MagazineArea(9, 1, 13, 7), .image)])]
			case .dark:
				[BlockSpec(isDark: true, slots: [.module(.darkStory, MagazineArea(1, 1, 13, 7), .longWithImage, columns: 2, dropCap: true)]),
				 BlockSpec(slots: [.module(.feature, MagazineArea(1, 1, 7, 4), .image, imageFraction: 0.5),
								   .module(.feature, MagazineArea(1, 4, 7, 7), .image, imageFraction: 0.5),
								   .module(.side, MagazineArea(7, 1, 13, 7), .image)])]
			case .text:
				[BlockSpec(slots: [.module(.lead, MagazineArea(1, 1, 8, 7), .long, columns: 2, dropCap: true),
								   .briefs(MagazineArea(8, 1, 13, 7), count: 4, columns: 2)]),
				 BlockSpec(slots: [.briefs(MagazineArea(1, 1, 13, 7), count: 8, columns: 2, title: NSLocalizedString("In Brief", comment: "Magazine: heading of a block of short articles"))])]
			}
		}

		var imagesNeeded: Int {
			switch self {
			case .opener, .text: 0
			case .newspaper, .dark: 3
			case .photo: 2
			}
		}
	}

	private static let rotation: [Group] = [.newspaper, .photo, .newspaper, .dark]
	private static let lookahead = 14

	static func blocks(for articles: [Article]) -> [MagazineBlock] {
		let sections = MagazineSections(accounts: AccountManager.shared.activeAccounts)
		var queue = deduplicated(articles.map { MagazineItem(article: $0, sections: sections) })
		var blocks = [MagazineBlock]()
		var groupIndex = 0
		var previousGroup: Group?

		while !queue.isEmpty {
			let group = chooseGroup(queue, groupIndex, previous: previousGroup)
			groupIndex += 1
			previousGroup = group
			var photoItem: MagazineItem? // The story block next to the photo tells its story

			for blockSpec in group.blocks where !queue.isEmpty || photoItem != nil {
				var filled = [Int: MagazineSlot]()
				let order = blockSpec.slots.indices.sorted { blockSpec.slots[$0].kind.priority < blockSpec.slots[$1].kind.priority }

				for index in order {
					switch blockSpec.slots[index] {
					case .masthead:
						filled[index] = .masthead
					case let .module(style, area, kind, imageFraction, columns, dropCap):
						guard let item = take(&queue, kind) else {
							continue
						}
						if style == .photo {
							photoItem = item
						}
						filled[index] = .module(style: style, area: area, item: item, imageFraction: imageFraction, columns: columns, dropCap: dropCap)
					case let .storyOfPhoto(style, area, columns, dropCap):
						if let item = photoItem {
							filled[index] = .module(style: style, area: area, item: item, imageFraction: 0, columns: columns, dropCap: dropCap)
						}
					case let .briefs(area, count, columns, title):
						var items = [MagazineItem]()
						while items.count < count, let item = take(&queue, .brief) {
							items.append(item)
						}
						if !items.isEmpty {
							filled[index] = .briefs(area: area, items: items, columns: columns, title: title)
						}
					}
				}

				let slots = blockSpec.slots.indices.compactMap { filled[$0] }
				if slots.contains(where: { if case .masthead = $0 { false } else { true } }) {
					let id = "\(blocks.count) " + slots.flatMap(\.items).map(\.id).joined(separator: " ")
					blocks.append(MagazineBlock(id: id, isDark: blockSpec.isDark, slots: slots))
				}
			}
		}

		return blocks
	}
}

private extension MagazineLayout {

	/// The same story often comes from two feeds of one publisher, sometimes with a reworded title.
	/// Same title, same image, or same opening counts as the same story. Keeps the first.
	static func deduplicated(_ items: [MagazineItem]) -> [MagazineItem] {
		var seen = Set<String>()
		return items.filter { item in
			let title = item.title.lowercased().filter { $0.isLetter || $0.isNumber }
			let opening = String(item.text.prefix(80)).lowercased().filter { $0.isLetter || $0.isNumber }
			let keys = [
				title.isEmpty ? nil : "title " + title,
				item.imageURL.map { "image " + $0 },
				opening.count < 40 ? nil : "text " + opening
			].compactMap { $0 }
			if keys.contains(where: seen.contains) {
				return false
			}
			seen.formUnion(keys)
			return true
		}
	}

	static func take(_ queue: inout [MagazineItem], _ kind: Kind) -> MagazineItem? {
		guard !queue.isEmpty else {
			return nil
		}
		let window = queue.prefix(lookahead)
		if let index = window.firstIndex(where: kind.matches) {
			return queue.remove(at: index)
		}
		// Nothing long enough: the slot that wants text gets the most text there is.
		if case .longWithImage = kind, let index = window.firstIndex(where: Kind.long.matches) {
			return queue.remove(at: index)
		}
		if kind == .long || kind == .longWithImage, let longest = window.indices.max(by: { queue[$0].text.count < queue[$1].text.count }) {
			return queue.remove(at: longest)
		}
		return queue.remove(at: queue.startIndex)
	}

	/// Never the same group twice in a row, so the magazine alternates between heavy and light.
	static func chooseGroup(_ queue: [MagazineItem], _ index: Int, previous: Group?) -> Group {
		if index == 0 {
			return .opener
		}
		let window = queue.prefix(lookahead)
		let images = window.filter(\.hasImage).count
		for offset in 0..<rotation.count {
			let group = rotation[(index - 1 + offset) % rotation.count]
			if group == previous {
				continue
			}
			if case .photo = group, !window.contains(where: Kind.photo.matches) {
				continue
			}
			if images >= group.imagesNeeded {
				return group
			}
		}
		return .text
	}
}
