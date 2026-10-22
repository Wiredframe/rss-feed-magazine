//
//  TimelineImageView.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit

/// Article image in a timeline cell. Fills its bounds, cropping as needed.
/// Shows a placeholder background until the image arrives.
final class TimelineImageView: NSView {

	var image: NSImage? {
		didSet {
			if image !== oldValue {
				needsDisplay = true
			}
		}
	}

	var cornerRadius: CGFloat = 0 {
		didSet {
			layer?.cornerRadius = cornerRadius
		}
	}

	override var wantsUpdateLayer: Bool {
		return true
	}

	nonisolated override var isFlipped: Bool {
		return true
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	override func updateLayer() {
		guard let layer else {
			return
		}
		layer.backgroundColor = NSColor.quaternarySystemFill.cgColor
		if let image {
			layer.contents = image.layerContents(forContentsScale: layer.contentsScale)
		} else {
			layer.contents = nil
		}
	}

	override func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		layer?.contentsScale = window?.backingScaleFactor ?? 2.0
		needsDisplay = true
	}
}

private extension TimelineImageView {

	func commonInit() {
		wantsLayer = true
		layerContentsRedrawPolicy = .onSetNeedsDisplay
		layer?.contentsGravity = .resizeAspectFill
		layer?.masksToBounds = true
	}
}
