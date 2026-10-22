//
//  MagazineView.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import SwiftUI
import Articles
import Account

/// What the magazine shows. The timeline view controller keeps fetching articles and feeds them in here.
@MainActor final class MagazineModel: ObservableObject {

	@Published private(set) var blocks = [MagazineBlock]()
	@Published private(set) var title = ""
	@Published private(set) var articleCount = 0
	@Published private(set) var statusRevision = 0 // Changes when articles are marked read, so views redraw

	var openArticle: ((Article) -> Void)?
	@Published var fadesReadArticles = AppDefaults.shared.magazineFadesReadArticles // View menu; never on paper

	private var articles = [Article]()

	/// The block at the leading edge. Saved per sidebar selection as the article it starts with,
	/// so the position survives new articles shifting the layout, switching folders, and quitting.
	@Published var leadingBlockID: String? {
		didSet {
			if leadingBlockID != oldValue, !isRestoringPosition {
				saveReadingPosition()
			}
		}
	}
	private var isRestoringPosition = false
	private static let readingPositionsKey = "magazineReadingPositions" // [sidebar title: articleID]

	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
	}

	func update(articles: [Article], title: String) {
		var needsRestore = false
		// Not just the IDs: a refresh can change an article, for instance give it an image.
		if articles != self.articles {
			self.articles = articles
			blocks = MagazineLayout.blocks(for: articles)
			articleCount = articles.count
			needsRestore = true
		}
		if title != self.title {
			self.title = title
			needsRestore = true
		}
		if needsRestore {
			restoreReadingPosition()
		}
	}

	var unreadCount: Int {
		blocks.reduce(0) { count, block in
			count + block.slots.reduce(0) { $0 + $1.items.filter { !$0.article.status.read }.count }
		}
	}

	@objc func statusesDidChange(_ note: Notification) {
		statusRevision += 1
	}
}

private extension MagazineModel {

	func saveReadingPosition() {
		guard !title.isEmpty, let block = blocks.first(where: { $0.id == leadingBlockID }), let article = block.slots.flatMap(\.items).first?.article else {
			return
		}
		var positions = UserDefaults.standard.dictionary(forKey: Self.readingPositionsKey) as? [String: String] ?? [:]
		positions[title] = article.articleID
		UserDefaults.standard.set(positions, forKey: Self.readingPositionsKey)
	}

	/// Back to the block with the saved article, or to the start if it’s gone.
	func restoreReadingPosition() {
		let positions = UserDefaults.standard.dictionary(forKey: Self.readingPositionsKey) as? [String: String] ?? [:]
		let savedArticleID = positions[title]
		let block = blocks.first { block in
			block.slots.flatMap(\.items).contains { $0.article.articleID == savedArticleID }
		}
		isRestoringPosition = true
		leadingBlockID = block?.id ?? blocks.first?.id
		isRestoringPosition = false
	}
}

struct MagazineView: View {

	@ObservedObject var model: MagazineModel

	var body: some View {
		GeometryReader { geometry in
			let metrics = MagazineMetrics(viewHeight: geometry.size.height)
			ScrollView(.horizontal, showsIndicators: true) {
				LazyHStack(alignment: .top, spacing: metrics.blockGap) {
					ForEach(visibleBlocks) { block in
						MagazineBlockView(block: block, metrics: metrics, model: model)
					}
				}
				.scrollTargetLayout()
			}
			.contentMargins(.horizontal, metrics.margin, for: .scrollContent) // Unlike padding, scroll positions keep this margin
			.scrollPosition(id: $model.leadingBlockID, anchor: .leading)
			.background(Color(nsColor: .textBackgroundColor))
		}
	}
}

extension MagazineView {

	/// Debug builds can start further in (MAGAZINE_SKIP_BLOCKS=n), for screenshots of later templates.
	var visibleBlocks: ArraySlice<MagazineBlock> {
		#if DEBUG
		let skip = Int(ProcessInfo.processInfo.environment["MAGAZINE_SKIP_BLOCKS"] ?? "") ?? 0
		return model.blocks.dropFirst(skip)
		#else
		return model.blocks[...]
		#endif
	}
}

/// Sizes follow the view’s height, so the magazine scales like a page would.
struct MagazineMetrics {
	let height: CGFloat
	let topMargin: CGFloat
	let bottomMargin: CGFloat
	let margin: CGFloat
	let blockWidth: CGFloat
	let blockGap: CGFloat
	let columnGap: CGFloat
	let rowGap: CGFloat
	let bodyFontSize: CGFloat
	let lineHeight: CGFloat // The baseline grid: body text in all modules sits on the same lines

	init(viewHeight: CGFloat) {
		let h = max(viewHeight, 400)
		self.height = h
		self.topMargin = floor(h * 0.04)
		self.bottomMargin = floor(h * 0.05)
		self.margin = floor(h * 0.05)
		self.blockWidth = floor(h * 0.74)
		self.blockGap = floor(h * 0.055)
		self.columnGap = floor(h * 0.028)
		self.rowGap = columnGap
		self.bodyFontSize = floor(h * 0.0175)
		self.lineHeight = MagazineTextNSView.lineHeight(forFontSize: bodyFontSize)
	}

	/// Headline sizes, from brief to story. Few clearly different steps, about 1.2 apart.
	static let headlineScale: [CGFloat] = [0.019, 0.022, 0.025, 0.029, 0.034, 0.041, 0.05, 0.062]

	var gridHeight: CGFloat {
		height - topMargin - bottomMargin
	}

	func size(_ factor: CGFloat) -> CGFloat {
		floor(height * factor)
	}

	func frame(for area: MagazineArea) -> CGRect {
		let columnWidth = (blockWidth - 5 * columnGap) / 6
		let rowHeight = (gridHeight - 11 * rowGap) / 12
		let x = CGFloat(area.column - 1) * (columnWidth + columnGap)
		let y = CGFloat(area.row - 1) * (rowHeight + rowGap)
		let columns = CGFloat(area.columnEnd - area.column)
		let rows = CGFloat(area.rowEnd - area.row)
		return CGRect(x: x, y: y, width: columns * columnWidth + (columns - 1) * columnGap, height: rows * rowHeight + (rows - 1) * rowGap)
	}
}

/// Colors for the paper and for the black blocks.
struct MagazineInk {
	let headline: Color
	let body: NSColor
	let meta: Color
	let rule: Color

	static let paper = MagazineInk(headline: Color(nsColor: .labelColor), body: NSColor.labelColor.withAlphaComponent(0.82), meta: Color(nsColor: .secondaryLabelColor), rule: Color(nsColor: .separatorColor))
	static let dark = MagazineInk(headline: .white, body: NSColor(white: 0.82, alpha: 1), meta: Color(white: 0.55), rule: Color(white: 0.3))
	static let readOpacity = 0.4
}

struct MagazineBlockView: View {

	let block: MagazineBlock
	let metrics: MagazineMetrics
	@ObservedObject var model: MagazineModel

	var body: some View {
		let ink = block.isDark ? MagazineInk.dark : MagazineInk.paper
		// One wash of color per block at most, on its first text-only module. More would lose the effect.
		let tintedIndex = block.slots.firstIndex(where: \.isTextOnly)
		ZStack(alignment: .topLeading) {
			ForEach(Array(block.slots.enumerated()), id: \.offset) { index, slot in // Slots never move within a block
				slotView(slot, ink: ink, isTinted: index == tintedIndex)
			}
		}
		.frame(width: metrics.blockWidth, height: metrics.gridHeight, alignment: .topLeading)
		.coordinateSpace(name: MagazineText.gridSpace)
		.padding(.top, metrics.topMargin)
		.padding(.bottom, metrics.bottomMargin)
		.background {
			if block.isDark {
				// A black band from top to bottom, wider than the block, like a dark page in the magazine.
				// The story’s image fills it faintly and fades to black behind the text.
				ZStack {
					// On a printed page the whole page is black already; a second black layer would leave a seam.
					if !drawsTextSeparately {
						Color.black
					}
					// In a PDF an empty, translucent image layer would still leave a seam at its edges.
					if let imageURL = block.slots.flatMap(\.items).first?.imageURL, !drawsTextSeparately || TimelineImageDownloader.shared.cachedImage(for: imageURL) != nil {
						MagazineImage(url: imageURL, smallImageAlignment: .top, showsPlaceholder: false)
							.opacity(0.75)
							.overlay {
								if drawsTextSeparately {
									// ImageRenderer draws gradients in PDF as solid black, hiding the image. Bands look the same on paper.
									VStack(spacing: 0) {
										ForEach(0..<48, id: \.self) { band in
											Color.black.opacity(Self.fadeOpacity(at: (Double(band) + 0.5) / 48))
										}
									}
								} else {
									LinearGradient(stops: Self.fadeStops.map { .init(color: .black.opacity($0.opacity), location: $0.location) }, startPoint: .top, endPoint: .bottom)
								}
							}
					}
				}
				.padding(.horizontal, -metrics.blockGap / 2)
			}
		}
		.environment(\.colorScheme, block.isDark ? .dark : colorScheme)
	}

	@Environment(\.colorScheme) private var colorScheme

	/// How the black page’s image fades to black toward the text.
	static let fadeStops: [(location: Double, opacity: Double)] = [(0, 0), (0.25, 0.15), (0.45, 0.6), (0.65, 0.93), (1, 0.93)]

	static func fadeOpacity(at location: Double) -> Double {
		for (a, b) in zip(fadeStops, fadeStops.dropFirst()) where location <= b.location {
			return a.opacity + (b.opacity - a.opacity) * (location - a.location) / (b.location - a.location)
		}
		return fadeStops.last?.opacity ?? 1
	}
	@Environment(\.magazineDrawsTextSeparately) private var drawsTextSeparately // Set while rendering a PDF page

	@ViewBuilder
	private func slotView(_ slot: MagazineSlot, ink: MagazineInk, isTinted: Bool) -> some View {
		switch slot {
		case .masthead:
			let frame = metrics.frame(for: MagazineArea(1, 1, 3, 7))
			MagazineMasthead(title: model.title, articleCount: model.articleCount, unreadCount: model.unreadCount, metrics: metrics)
				.frame(width: frame.width, height: frame.height)
				.offset(x: frame.minX, y: frame.minY)
		case let .module(style, area, item, imageFraction, columns, dropCap):
			let frame = metrics.frame(for: area)
			MagazineModuleView(style: style, item: item, imageFraction: imageFraction, columns: columns, dropCap: dropCap, metrics: metrics, ink: ink, size: frame.size, isTinted: isTinted, model: model)
				.frame(width: frame.width, height: frame.height, alignment: .topLeading)
				.offset(x: frame.minX, y: frame.minY)
		case let .briefs(area, items, columns, title):
			let frame = metrics.frame(for: area)
			MagazineBriefsView(items: items, columns: columns, title: title, metrics: metrics, ink: ink, isTinted: isTinted, model: model)
				.frame(width: frame.width, height: frame.height, alignment: .topLeading)
				.offset(x: frame.minX, y: frame.minY)
		}
	}
}

struct MagazineMasthead: View {

	let title: String
	let articleCount: Int
	let unreadCount: Int
	let metrics: MagazineMetrics

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Spacer(minLength: 0)
			Text(title)
				.font(.system(size: metrics.size(0.1), weight: .bold, design: .serif))
				.lineLimit(1)
				.minimumScaleFactor(0.4)
			Rectangle().frame(height: 1)
				.padding(.top, metrics.size(0.008))
			HStack {
				Text(Date().formatted(date: .complete, time: .omitted))
				Spacer()
				Text(String(format: NSLocalizedString("%d articles, %d unread", comment: "Magazine masthead"), articleCount, unreadCount))
			}
			.font(.system(size: metrics.size(0.0135), weight: .medium))
			.foregroundStyle(.secondary)
			.padding(.vertical, metrics.size(0.006))
			Rectangle().frame(height: 3)
		}
	}
}

struct MagazineModuleView: View {

	let style: MagazineModuleStyle
	let item: MagazineItem
	let imageFraction: CGFloat
	let columns: Int
	let dropCap: Bool
	let metrics: MagazineMetrics
	let ink: MagazineInk
	let size: CGSize
	let isTinted: Bool // A light wash of the section’s color, so pages with few images aren’t all black and white
	@ObservedObject var model: MagazineModel

	private var isRead: Bool {
		_ = model.statusRevision
		return item.article.status.read
	}

	var body: some View {
		Group {
			switch style {
			case .photo:
				MagazineImage(url: item.imageURL, smallImageAlignment: .top)
					.overlay(alignment: .bottomLeading) {
						Text(item.title)
							.font(.system(size: metrics.size(0.013), weight: .medium))
							.foregroundStyle(.white)
							.shadow(color: .black.opacity(0.6), radius: 3)
							.padding(metrics.size(0.02))
					}
			case .side:
				HStack(alignment: .top, spacing: metrics.columnGap) {
					if item.hasImage {
						MagazineImage(url: item.imageURL)
							.frame(width: (size.width - metrics.columnGap) / 2)
					}
					textStack(textColumns: 1)
				}
			case .story, .darkStory, .lead:
				textStack(textColumns: columns)
			case .hero, .feature:
				VStack(alignment: .leading, spacing: 0) {
					if item.hasImage {
						MagazineImage(url: item.imageURL)
							.frame(height: floor(size.height * imageFraction))
							.padding(.bottom, metrics.size(0.012))
					}
					textStack(textColumns: columns)
				}
			}
		}
		.padding(isTinted ? tintPadding : 0)
		.background(isTinted ? item.accent.opacity(0.08) : Color.clear)
		.contentShape(Rectangle())
		.onTapGesture {
			model.openArticle?(item.article)
		}
		.onHover { inside in
			if inside {
				NSCursor.pointingHand.push()
			} else {
				NSCursor.pop()
			}
		}
		.opacity(isRead && model.fadesReadArticles ? MagazineInk.readOpacity : 1) // Read articles fade as a whole, image and all
	}

	private var tintPadding: CGFloat {
		metrics.size(0.018)
	}

	private func textStack(textColumns: Int) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			if style == .story || style == .darkStory {
				Spacer(minLength: 0).frame(maxHeight: style == .darkStory ? .infinity : 0)
			}
			MagazineKicker(item: item, metrics: metrics, ink: ink)
			Text(item.title)
				.font(.system(size: headlineSize, weight: isLargeHeadline ? .bold : .semibold, design: .serif))
				.foregroundStyle(ink.headline)
				.lineLimit(headlineLines)
				.lineSpacing(0)
				.fixedSize(horizontal: false, vertical: true)
				// Small: the text below moves down onto the baseline grid, which adds up to a line.
				.padding(.bottom, metrics.size(style == .story || style == .darkStory ? 0.012 : 0.003))
			MagazineText(configuration: MagazineTextConfiguration(
				text: item.text,
				fontSize: metrics.bodyFontSize, // One size for all body text
				color: ink.body,
				columns: textColumns,
				columnGap: metrics.columnGap,
				dropCap: dropCap,
				baselineGrid: metrics.lineHeight
			))
			.frame(maxWidth: .infinity, maxHeight: style == .darkStory ? metrics.gridHeight * 0.45 : .infinity)
		}
	}

	private var isLargeHeadline: Bool {
		switch style {
		case .hero, .lead, .story, .darkStory: true
		case .feature, .side, .photo: false
		}
	}

	private var headlineLines: Int {
		switch style {
		case .story, .darkStory, .side: 4
		default: 3
		}
	}

	/// The headline’s step on the scale follows the module’s rank and width. A title that wouldn’t fit
	/// in its lines goes down a step or two instead of running on.
	private var headlineSize: CGFloat {
		let defaultStep: Int = switch style {
		case .feature, .photo: 2
		case .side: 3
		case .lead: 5
		case .hero: 6
		case .story, .darkStory: 7
		}
		var width = size.width - (isTinted ? tintPadding * 2 : 0)
		if style == .side && item.hasImage {
			width = (width - metrics.columnGap) / 2
		}
		var step = defaultStep
		while step > max(0, defaultStep - 2) {
			let fontSize = metrics.size(MagazineMetrics.headlineScale[step])
			let charactersPerLine = max(1, width / (fontSize * 0.5))
			if ceil(CGFloat(item.title.count) / charactersPerLine) <= CGFloat(headlineLines) {
				break
			}
			step -= 1
		}
		return metrics.size(MagazineMetrics.headlineScale[step])
	}
}

struct MagazineKicker: View {

	let item: MagazineItem
	let metrics: MagazineMetrics
	let ink: MagazineInk

	var body: some View {
		HStack(alignment: .firstTextBaseline) {
			Text(item.feedName)
				.foregroundStyle(item.accent)
				.fontWeight(.semibold)
				.lineLimit(1)
			Spacer(minLength: metrics.size(0.01))
			Text(MagazineKicker.dateString(item.article.logicalDatePublished))
				.foregroundStyle(ink.meta)
		}
		.font(.system(size: metrics.size(0.0125)))
		.padding(.bottom, metrics.size(0.006))
	}

	static func dateString(_ date: Date) -> String {
		if Calendar.current.isDateInToday(date) {
			return date.formatted(date: .omitted, time: .shortened)
		}
		return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
	}
}

struct MagazineBriefsView: View {

	let items: [MagazineItem]
	let columns: Int
	let title: String?
	let metrics: MagazineMetrics
	let ink: MagazineInk
	let isTinted: Bool
	@ObservedObject var model: MagazineModel

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Rectangle().frame(height: 2).foregroundStyle(ink.headline)
			content
				.padding(.horizontal, isTinted ? metrics.size(0.018) : 0)
				.padding(.bottom, metrics.size(0.006))
				.background(isTinted ? (items.first?.accent ?? .secondary).opacity(0.08) : Color.clear)
		}
	}

	private var content: some View {
		let rows = Int(ceil(Double(items.count) / Double(columns)))
		return VStack(alignment: .leading, spacing: 0) {
			if let title {
				Text(title)
					.font(.system(size: metrics.size(0.022), weight: .bold, design: .serif))
					.padding(.top, metrics.size(0.012))
			}
			Grid(horizontalSpacing: metrics.columnGap, verticalSpacing: 0) {
				ForEach(0..<rows, id: \.self) { row in
					GridRow {
						ForEach(0..<columns, id: \.self) { column in
							let index = row * columns + column
							if index < items.count {
								brief(items[index], showsRule: row > 0)
							} else {
								Color.clear
							}
						}
					}
				}
			}
			.padding(.top, metrics.size(0.012))
		}
	}

	private func brief(_ item: MagazineItem, showsRule: Bool) -> some View {
		let isRead = { _ = model.statusRevision; return item.article.status.read }()
		return VStack(alignment: .leading, spacing: 0) {
			if showsRule {
				Rectangle().frame(height: 1).foregroundStyle(ink.rule)
					.padding(.bottom, metrics.size(0.01))
			}
			VStack(alignment: .leading, spacing: 0) {
				MagazineKicker(item: item, metrics: metrics, ink: ink)
				Text(item.title)
					.font(.system(size: metrics.size(0.0185), weight: .semibold, design: .serif))
					.foregroundStyle(ink.headline)
					.lineLimit(3)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.bottom, metrics.size(0.006))
				MagazineText(configuration: MagazineTextConfiguration(text: item.text, fontSize: metrics.bodyFontSize, color: ink.body, justified: false, baselineGrid: metrics.lineHeight))
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			.opacity(isRead && model.fadesReadArticles ? MagazineInk.readOpacity : 1) // The rule above stays, it belongs to the grid
		}
		.padding(.bottom, metrics.size(0.012))
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.contentShape(Rectangle())
		.onTapGesture {
			model.openArticle?(item.article)
		}
	}
}

/// An article image, filling its frame. Small images are shown whole instead of blown up.
struct MagazineImage: View {

	let url: String?
	let smallImageAlignment: Alignment // Full-page images go to the top, so the text below stays on black
	let showsPlaceholder: Bool // Not behind the black page: a gray box would show if the image doesn’t load
	@State private var image: NSImage?

	init(url: String?, smallImageAlignment: Alignment = .center, showsPlaceholder: Bool = true) {
		self.url = url
		self.smallImageAlignment = smallImageAlignment
		self.showsPlaceholder = showsPlaceholder
		// Cached images show right away, without a placeholder first. The PDF export relies on it.
		_image = State(initialValue: url.flatMap { TimelineImageDownloader.shared.cachedImage(for: $0) })
	}

	var body: some View {
		GeometryReader { geometry in
			ZStack {
				Color.primary.opacity(showsPlaceholder && !hasFailed ? 0.06 : 0) // A broken image leaves white, not a gray box
				if let image {
					let isSmall = image.size.width < geometry.size.width * 0.6
					Image(nsImage: image)
						.resizable()
						.interpolation(.high)
						.aspectRatio(contentMode: isSmall ? .fit : .fill)
						.frame(width: geometry.size.width, height: geometry.size.height, alignment: isSmall ? smallImageAlignment : .center)
				}
			}
			.clipped()
		}
		// SwiftUI reuses this view for other articles while scrolling. Start over when the URL changes.
		.task(id: url) {
			image = nil
			loadImage()
		}
		.onReceive(NotificationCenter.default.publisher(for: .timelineImageDidBecomeAvailable)) { note in
			if let url, note.userInfo?["url"] as? String == url {
				loadImage()
			}
		}
	}

	@State private var hasFailed = false

	private func loadImage() {
		guard let url else {
			return
		}
		image = TimelineImageDownloader.shared.image(for: url)
		hasFailed = image == nil && TimelineImageDownloader.shared.hasFailed(url)
	}
}

extension MagazineSlot {

	/// Modules without an image: these can carry the block’s wash of color.
	var isTextOnly: Bool {
		switch self {
		case .masthead: false
		case .briefs: true
		case let .module(style, _, item, _, _, _):
			switch style {
			case .lead: true
			case .feature, .side, .hero: !item.hasImage
			case .story, .darkStory, .photo: false
			}
		}
	}

	var items: [MagazineItem] {
		switch self {
		case .masthead: []
		case let .module(_, _, item, _, _, _): [item]
		case let .briefs(_, items, _, _): items
		}
	}
}
