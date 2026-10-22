//
//  TimelineTableRowView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/31/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import AppKit

final class TimelineTableRowView: NSTableRowView {

	private var separator: NSView?

	override var isOpaque: Bool {
		return true
	}

	override var isEmphasized: Bool {
		didSet {
			cellView?.isEmphasized = isEmphasized
		}
	}

	override var isSelected: Bool {
		didSet {
			cellView?.isSelected = isSelected
			updateSeparatorVisibility()
		}
	}

	// The selection is drawn with rounded corners. Like Mail, don’t draw a separator touching it.
	override var isNextRowSelected: Bool {
		didSet {
			updateSeparatorVisibility()
		}
	}

	init() {
		super.init(frame: NSRect.zero)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	private var cellView: TimelineTableCellView? {
		for oneSubview in subviews {
			if let foundView = oneSubview as? TimelineTableCellView {
				return foundView
			}
		}
		return nil
	}

	override func viewDidMoveToSuperview() {
		if AppDefaults.shared.timelineShowsSeparators {
			addSeparatorView()
		}
	}

	override func layout() {
		super.layout()
		layoutSeparator()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		needsLayout = true
	}

	private func addSeparatorView() {
		guard separator == nil else {
			return
		}
		let separator = NSView()
		separator.wantsLayer = true
		addSubview(separator)
		self.separator = separator
		updateSeparatorVisibility()
		needsLayout = true
	}

	/// A hairline from the start of the text to its end, so it lines up with titles and images.
	private func layoutSeparator() {
		guard let separator, let cellView else {
			return
		}
		effectiveAppearance.performAsCurrentDrawingAppearance {
			separator.layer?.backgroundColor = Assets.Colors.timelineSeparator.cgColor
		}
		let insets = cellView.textHorizontalInsets
		let lineWidth = 1.0 / (window?.backingScaleFactor ?? 2.0)
		let minX = cellView.frame.minX + insets.leading
		let maxX = cellView.frame.maxX - insets.trailing
		let y = isFlipped ? bounds.maxY - lineWidth : bounds.minY
		separator.frame = NSRect(x: minX, y: y, width: max(0, maxX - minX), height: lineWidth)
	}

	private func updateSeparatorVisibility() {
		separator?.isHidden = isSelected || isNextRowSelected
	}

}
