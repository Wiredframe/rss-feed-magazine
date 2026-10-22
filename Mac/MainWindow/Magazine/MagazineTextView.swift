//
//  MagazineTextView.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import SwiftUI
import NaturalLanguage

/// Text that flows through columns, justified and hyphenated, optionally with a drop cap.
/// Text that doesn’t fit ends with an ellipsis after the last whole word.
/// SwiftUI’s Text can’t flow across columns, so this uses TextKit.
struct MagazineText: View {

	let configuration: MagazineTextConfiguration
	@State private var topInset: CGFloat = 0
	@Environment(\.magazineDrawsTextSeparately) private var drawsTextSeparately

	var body: some View {
		var configuration = configuration
		configuration.topInset = topInset
		return Group {
			if drawsTextSeparately {
				Color.clear // The PDF export draws the text views itself; SwiftUI can’t render them
			} else {
				MagazineTextRepresentable(configuration: configuration)
			}
		}
			.background {
				GeometryReader { proxy in
					let top = proxy.frame(in: .named(MagazineText.gridSpace)).minY
					Color.clear
						.onAppear { updateTopInset(top) }
						.onChange(of: top) { _, newTop in updateTopInset(newTop) }
				}
			}
	}

	/// The coordinate space of a magazine block. Blocks share their top, so the grid is the same in all of them.
	static let gridSpace = "magazineBlock"

	/// Moves the first line down onto the baseline grid.
	private func updateTopInset(_ top: CGFloat) {
		let grid = configuration.baselineGrid
		guard grid > 0 else {
			return
		}
		let remainder = top.truncatingRemainder(dividingBy: grid)
		let inset = remainder < 0.5 || grid - remainder < 0.5 ? 0 : grid - remainder
		if abs(inset - topInset) > 0.5 {
			topInset = inset
		}
	}
}

private struct MagazineDrawsTextSeparatelyKey: EnvironmentKey {
	static let defaultValue = false
}

extension EnvironmentValues {
	var magazineDrawsTextSeparately: Bool {
		get { self[MagazineDrawsTextSeparatelyKey.self] }
		set { self[MagazineDrawsTextSeparatelyKey.self] = newValue }
	}
}

private struct MagazineTextRepresentable: NSViewRepresentable {

	let configuration: MagazineTextConfiguration

	func makeNSView(context: Context) -> MagazineTextNSView {
		MagazineTextNSView()
	}

	func updateNSView(_ view: MagazineTextNSView, context: Context) {
		view.configuration = configuration
	}
}

struct MagazineTextConfiguration: Equatable {
	var text: String
	var fontSize: CGFloat
	var color: NSColor
	var columns = 1
	var columnGap: CGFloat = 0
	var dropCap = false
	var justified = true
	var baselineGrid: CGFloat = 0 // When set, the first line moves down onto the grid shared by all magazine text
	var topInset: CGFloat = 0
}

final class MagazineTextNSView: NSView {

	var configuration = MagazineTextConfiguration(text: "", fontSize: 13, color: .labelColor) {
		didSet {
			if configuration != oldValue {
				invalidateTextLayout()
			}
		}
	}

	private var textLayout: TextLayout?

	nonisolated override var isFlipped: Bool {
		return true
	}

	nonisolated static func lineHeight(forFontSize fontSize: CGFloat) -> CGFloat {
		ceil(fontSize * lineHeightMultiple)
	}

	override func setFrameSize(_ newSize: NSSize) {
		if newSize != frame.size {
			invalidateTextLayout()
		}
		super.setFrameSize(newSize)
	}

	override func draw(_ dirtyRect: NSRect) {
		guard bounds.width > 1, bounds.height > 1 else {
			return
		}
		let offset = configuration.topInset
		let layout = textLayout ?? makeTextLayout(height: bounds.height - offset)
		textLayout = layout

		for (index, container) in layout.containers.enumerated() {
			let glyphRange = layout.layoutManager.glyphRange(for: container)
			let origin = NSPoint(x: CGFloat(index) * (layout.columnWidth + configuration.columnGap), y: offset)
			layout.layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
			layout.layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
		}
		if let dropCap = layout.dropCap {
			dropCap.string.draw(at: NSPoint(x: dropCap.origin.x, y: dropCap.origin.y + offset))
		}
	}
}

private extension MagazineTextNSView {

	struct DropCap {
		let string: NSAttributedString
		let origin: NSPoint
	}

	struct TextLayout {
		let layoutManager: NSLayoutManager
		let containers: [NSTextContainer]
		let columnWidth: CGFloat
		let dropCap: DropCap?
		let storage: NSTextStorage // The layout manager doesn’t retain it
	}

	nonisolated static let lineHeightMultiple: CGFloat = 1.42
	static let dropCapLines: CGFloat = 3

	func invalidateTextLayout() {
		textLayout = nil
		needsDisplay = true
	}

	func makeTextLayout(height: CGFloat) -> TextLayout {
		let config = configuration
		let columns = max(1, config.columns)
		let columnWidth = floor((bounds.width - CGFloat(columns - 1) * config.columnGap) / CGFloat(columns))
		let lineHeight = Self.lineHeight(forFontSize: config.fontSize)
		// Whole lines only, so the last line of a column is never cut in half.
		let columnHeight = max(0, floor(height / lineHeight) * lineHeight)

		var body = config.text
		var dropCap: DropCap?
		var exclusion: NSRect?
		if config.dropCap, body.count > 120, let first = body.first, first.isLetter {
			body.removeFirst()
			// The cap runs from the cap height of the first line down to the baseline of the third,
			// so measure where TextKit puts the first baseline and size the cap by its cap height.
			let bodyFont = Self.serifFont(size: config.fontSize, weight: .regular)
			let probe = layout("H", columns: 1, columnWidth: columnWidth, columnHeight: 1_000_000, lineHeight: lineHeight, exclusion: nil, dropCap: nil)
			let firstBaseline = probe.layoutManager.location(forGlyphAt: 0).y
			let capTop = firstBaseline - bodyFont.capHeight
			let capBaseline = firstBaseline + lineHeight * (Self.dropCapLines - 1)
			let unitFont = Self.serifFont(size: 100, weight: .bold)
			let capFont = Self.serifFont(size: (capBaseline - capTop) / unitFont.capHeight * 100, weight: .bold)
			let capString = NSAttributedString(string: String(first), attributes: [.font: capFont, .foregroundColor: config.color])
			let capSize = capString.size()
			dropCap = DropCap(string: capString, origin: NSPoint(x: 0, y: capBaseline - capFont.ascender))
			exclusion = NSRect(x: 0, y: 0, width: ceil(capSize.width) + config.fontSize * 0.4, height: lineHeight * Self.dropCapLines)
		}

		// Text that fits is balanced across the columns, instead of filling the first and leaving a line in the last.
		var balancedHeight = columnHeight
		if columns > 1 {
			let single = layout(body, columns: 1, columnWidth: columnWidth, columnHeight: 1_000_000, lineHeight: lineHeight, exclusion: exclusion, dropCap: dropCap)
			let usedHeight = single.layoutManager.usedRect(for: single.containers[0]).height
			let lines = ceil(usedHeight / lineHeight)
			let height = ceil(lines / CGFloat(columns)) * lineHeight
			if height < columnHeight {
				balancedHeight = height
			}
		}
		if let exclusion {
			balancedHeight = max(balancedHeight, exclusion.height)
		}

		var visibleText = body
		while true {
			let layout = layout(visibleText, columns: columns, columnWidth: columnWidth, columnHeight: balancedHeight, lineHeight: lineHeight, exclusion: exclusion, dropCap: dropCap)
			guard let lastContainer = layout.containers.last else {
				return loosenedLines(layout)
			}
			let lastGlyphRange = layout.layoutManager.glyphRange(for: lastContainer)
			let glyphCount = layout.layoutManager.numberOfGlyphs
			if NSMaxRange(lastGlyphRange) >= glyphCount {
				return loosenedLines(layout)
			}
			// Balancing can come out a line short, since breaks differ between one column and several.
			if balancedHeight < columnHeight {
				balancedHeight = min(balancedHeight + lineHeight, columnHeight)
				continue
			}
			// Too long: cut after the last word that fits, minus one for the ellipsis, and try again.
			let fittingCharacters = layout.layoutManager.characterIndexForGlyph(at: NSMaxRange(lastGlyphRange))
			let truncated = Self.text(visibleText, truncatedBefore: min(fittingCharacters, visibleText.utf16.count))
			if truncated == visibleText || truncated.isEmpty {
				return loosenedLines(layout)
			}
			visibleText = truncated
		}
	}

	func layout(_ text: String, columns: Int, columnWidth: CGFloat, columnHeight: CGFloat, lineHeight: CGFloat, exclusion: NSRect?, dropCap: DropCap?) -> TextLayout {
		let config = configuration
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.minimumLineHeight = lineHeight
		paragraphStyle.maximumLineHeight = lineHeight
		// Justification needs about 40 characters a line; narrower columns are set ragged right.
		let isWideEnoughToJustify = columnWidth >= config.fontSize * 20
		paragraphStyle.alignment = config.justified && isWideEnoughToJustify ? .justified : .natural
		paragraphStyle.hyphenationFactor = 1.0

		var attributes: [NSAttributedString.Key: Any] = [
			.font: Self.serifFont(size: config.fontSize, weight: .regular),
			.foregroundColor: config.color,
			.paragraphStyle: paragraphStyle
		]
		if let language = Self.language(of: text) {
			attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language
		}

		let storage = NSTextStorage(string: text, attributes: attributes)
		let layoutManager = NSLayoutManager()
		storage.addLayoutManager(layoutManager)

		var containers = [NSTextContainer]()
		for index in 0..<columns {
			let container = NSTextContainer(size: NSSize(width: columnWidth, height: columnHeight))
			container.lineFragmentPadding = 0
			if index == 0, let exclusion {
				container.exclusionPaths = [NSBezierPath(rect: exclusion)]
			}
			layoutManager.addTextContainer(container)
			containers.append(container)
		}
		layoutManager.ensureLayout(for: containers[containers.count - 1])

		return TextLayout(layoutManager: layoutManager, containers: containers, columnWidth: columnWidth, dropCap: dropCap, storage: storage)
	}

	/// Justification spreads the letters of lines with too few spaces, next to a drop cap or with long words.
	/// Ending such a line with a line separator sets it ragged instead, and the rest of the paragraph stays justified.
	/// Replacing a space keeps the text’s length, so the line breaks and the truncation stay the same.
	func loosenedLines(_ layout: TextLayout) -> TextLayout {
		guard configuration.justified, layout.columnWidth >= configuration.fontSize * 20 else {
			return layout // Ragged already
		}
		let layoutManager = layout.layoutManager
		let storage = layout.storage
		let string = storage.string as NSString
		let maximumGapPerSpace = configuration.fontSize * 0.5
		var loosenedLineEnds = [Int]()

		var glyphIndex = 0
		while glyphIndex < layoutManager.numberOfGlyphs {
			var lineGlyphRange = NSRange()
			let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
			glyphIndex = NSMaxRange(lineGlyphRange)
			guard lineGlyphRange.length > 0, layoutManager.textContainer(forGlyphAt: lineGlyphRange.location, effectiveRange: nil) != nil else {
				break
			}
			let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
			let lastIndex = NSMaxRange(characterRange) - 1
			// Only lines that break at a space: not the last line, not hyphenated ones.
			guard NSMaxRange(characterRange) < string.length, string.character(at: lastIndex) == Self.space else {
				continue
			}
			let words = NSRange(location: characterRange.location, length: characterRange.length - 1)
			let naturalWidth = storage.attributedSubstring(from: words).size().width
			let spaces = string.substring(with: words).filter { $0 == " " }.count
			let gap = lineRect.width - naturalWidth
			if gap > 1 && (spaces == 0 || gap / CGFloat(spaces) > maximumGapPerSpace) {
				loosenedLineEnds.append(lastIndex)
			}
		}

		for index in loosenedLineEnds.reversed() {
			storage.replaceCharacters(in: NSRange(location: index, length: 1), with: "\u{2028}")
		}
		if !loosenedLineEnds.isEmpty, let lastContainer = layout.containers.last {
			layoutManager.ensureLayout(for: lastContainer)
		}
		return layout
	}

	static let space = unichar(UInt8(ascii: " "))

	/// Cuts at the last space before `utf16Offset`, drops one more word to make room, and appends an ellipsis.
	static func text(_ text: String, truncatedBefore utf16Offset: Int) -> String {
		let end = String.Index(utf16Offset: utf16Offset, in: text)
		var prefix = text[..<end]
		for _ in 0..<2 {
			guard let space = prefix.lastIndex(of: " ") else {
				return ""
			}
			prefix = prefix[..<space]
		}
		let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–-"))
		return trimmed + " …"
	}

	static func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
		let system = NSFont.systemFont(ofSize: size, weight: weight)
		guard let descriptor = system.fontDescriptor.withDesign(.serif) else {
			return system
		}
		return NSFont(descriptor: descriptor, size: size) ?? system
	}

	static func language(of text: String) -> String? {
		let recognizer = NLLanguageRecognizer()
		recognizer.processString(String(text.prefix(400)))
		return recognizer.dominantLanguage?.rawValue
	}
}
