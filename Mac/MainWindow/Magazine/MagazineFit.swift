//
//  MagazineFit.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 11/2/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit

/// Estimates how much room an article’s text takes, so the layout can size modules to their content
/// instead of leaving short texts in big empty boxes. All sizes scale with the view’s height,
/// so measuring once at a reference height holds for every window size.
@MainActor enum MagazineFit {

	static let metrics = MagazineMetrics(viewHeight: 1000)

	/// The wash of color around the first text-only module of a block.
	static var tintPadding: CGFloat {
		metrics.size(0.018)
	}

	/// Height of kicker, headline, and body text of a module whose text is `width` wide.
	static func stackHeight(style: MagazineModuleStyle, item: MagazineItem, width: CGFloat, columns: Int, dropCap: Bool) -> CGFloat {
		let headlineSize = MagazineModuleView.headlineSize(style: style, title: item.title, width: width, metrics: metrics)
		let weight: NSFont.Weight = MagazineModuleView.isLargeHeadline(style) ? .bold : .semibold
		let headline = headlineHeight(item.title, width: width, fontSize: headlineSize, weight: weight, maxLines: MagazineModuleView.headlineLines(style))
		let headlinePadding = metrics.size(style == .story || style == .darkStory ? 0.012 : 0.003)
		let text = textHeight(item.text, width: width, columns: columns, dropCap: dropCap)
		// Plus a line: the text moves down onto the baseline grid.
		return kickerHeight + headline + headlinePadding + text + metrics.lineHeight
	}

	/// Height of one brief in a column `width` wide, showing at most `maxLines` of its text.
	static func briefHeight(_ item: MagazineItem, width: CGFloat, showsRule: Bool, maxLines: Int) -> CGFloat {
		let rule = showsRule ? 1 + metrics.size(0.01) : 0
		let headline = headlineHeight(item.title, width: width, fontSize: metrics.size(0.0185), weight: .semibold, maxLines: 3)
		let lines = textLines(item.text, width: width, maxLines: maxLines)
		let text = lines > 0 ? (lines + 0.5) * metrics.lineHeight : 0 // Plus, on average, the move onto the grid
		return rule + kickerHeight + headline + metrics.size(0.006) + text + metrics.size(0.012)
	}

	/// Body text, balanced over `columns` columns as MagazineText sets it.
	static func textHeight(_ text: String, width: CGFloat, columns: Int, dropCap: Bool) -> CGFloat {
		let columns = max(1, columns)
		let columnWidth = (width - CGFloat(columns - 1) * metrics.columnGap) / CGFloat(columns)
		var lines = textLines(text, width: columnWidth, maxLines: maxLinesPerColumn * columns)
		if dropCap && text.count > 120 {
			lines = max(lines + 1, 3) // The cap pushes the first three lines in
		}
		return ceil(lines / CGFloat(columns)) * metrics.lineHeight
	}
}

private extension MagazineFit {

	static var kickerHeight: CGFloat {
		ceil(metrics.size(0.0125) * 1.25) + metrics.size(0.006)
	}

	struct MeasuredText: Hashable {
		let text: String
		let width: CGFloat
	}

	static var measuredLines = [MeasuredText: CGFloat]()

	/// More than a module’s whole height; longer texts are cut anyway.
	static let maxLinesPerColumn = 20

	static let bodyAttributes: [NSAttributedString.Key: Any] = {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.minimumLineHeight = metrics.lineHeight
		paragraphStyle.maximumLineHeight = metrics.lineHeight
		paragraphStyle.hyphenationFactor = 1.0
		return [
			.font: MagazineTextNSView.serifFont(size: metrics.bodyFontSize, weight: .regular),
			.paragraphStyle: paragraphStyle
		]
	}()

	/// Lines the text takes, up to `maxLines`. Only about as much text as fits is measured, which keeps it fast.
	static func textLines(_ text: String, width: CGFloat, maxLines: Int) -> CGFloat {
		guard !text.isEmpty, width > 0 else {
			return 0
		}
		let charactersPerLine = Int(width / (metrics.bodyFontSize * 0.35)) // Generous: more than a line ever holds
		if text.count > (maxLines + 1) * charactersPerLine {
			return CGFloat(maxLines) // Takes all the lines there are, no need to measure
		}
		// The layout runs again on every refresh, with mostly the same articles.
		let key = MeasuredText(text: text, width: width)
		if let lines = measuredLines[key] {
			return min(lines, CGFloat(maxLines))
		}
		let string = NSAttributedString(string: text, attributes: bodyAttributes)
		let rect = string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
		let lines = max(1, round(rect.height / metrics.lineHeight))
		if measuredLines.count > 20_000 {
			measuredLines.removeAll()
		}
		measuredLines[key] = lines
		return min(lines, CGFloat(maxLines))
	}

	static func headlineHeight(_ title: String, width: CGFloat, fontSize: CGFloat, weight: NSFont.Weight, maxLines: Int) -> CGFloat {
		guard !title.isEmpty, width > 0 else {
			return 0
		}
		let font = headlineFont(size: fontSize, weight: weight)
		let string = NSAttributedString(string: title, attributes: [.font: font])
		let rect = string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
		let lineHeight = ceil(font.ascender - font.descender + font.leading)
		return min(ceil(rect.height), CGFloat(maxLines) * lineHeight)
	}

	static var headlineFonts = [String: NSFont]()

	/// Building a serif font takes a font descriptor lookup; the layout asks for the same few sizes thousands of times.
	static func headlineFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
		let key = "\(size) \(weight.rawValue)"
		if let font = headlineFonts[key] {
			return font
		}
		let font = MagazineTextNSView.serifFont(size: size, weight: weight)
		headlineFonts[key] = font
		return font
	}
}
