//
//  MagazinePDFExporter.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import SwiftUI
import PDFKit
import Articles

/// Exports the magazine as an A4 PDF: one block per page, with running head, page numbers,
/// and a link on every article. The pages are the magazine’s own block views, drawn into PDF,
/// so text stays text.
@MainActor final class MagazinePDFExporter {

	static let pageSize = NSSize(width: 595, height: 842) // A4 in points

	private let model = MagazineModel()
	private let metrics: MagazineMetrics
	private let headHeight: CGFloat

	init(articles: [Article], title: String) {
		// Size the block so it fills the page’s width with the magazine’s own side margins.
		let blockHeight = floor(Self.pageSize.width / 0.84)
		metrics = MagazineMetrics(viewHeight: blockHeight)
		headHeight = floor((Self.pageSize.height - metrics.height) / 2)
		model.fadesReadArticles = false
		model.update(articles: articles, title: title)
	}

	var pageCount: Int {
		model.blocks.count
	}

	/// Writes the file only at the end, so a cancelled export leaves nothing behind.
	/// `progress` is called before each page with its number.
	func export(to url: URL, progress: ((Int) -> Void)? = nil) async throws {
		let document = PDFDocument()
		let date = Date().formatted(date: .long, time: .omitted)

		for (index, block) in model.blocks.enumerated() {
			try Task.checkCancellation()
			progress?(index + 1)
			await loadImages(for: block)
			let pageView = MagazinePDFPage(block: block, metrics: metrics, model: model, pageNumber: index + 1, title: model.title, date: date, headHeight: headHeight)
			guard let data = await pdfData(for: pageView), let page = PDFDocument(data: data)?.page(at: 0) else {
				continue
			}
			addLinks(for: block, to: page)
			document.insert(page, at: document.pageCount)
		}

		document.documentAttributes = [PDFDocumentAttribute.titleAttribute: model.title, PDFDocumentAttribute.creatorAttribute: "RSS Feed Magazine"]
		guard document.write(to: url) else {
			throw CocoaError(.fileWriteUnknown)
		}
	}
}

private extension MagazinePDFExporter {

	/// In the app images arrive while scrolling; on paper they have to be there.
	func loadImages(for block: MagazineBlock) async {
		let urls = Set(block.slots.flatMap(\.items).compactMap(\.imageURL))
		for url in urls {
			_ = await TimelineImageDownloader.shared.loadImage(url)
		}
	}

	/// Draws one page as vector PDF in two passes. SwiftUI’s ImageRenderer draws everything but the TextKit
	/// text views, which it can’t render; those are laid out in an offscreen window first and drawn into the
	/// same page at their positions. (NSView’s dataWithPDF would do the opposite: only the text views.)
	func pdfData(for pageView: MagazinePDFPage) async -> Data? {
		let size = Self.pageSize
		let frame = NSRect(origin: .zero, size: size)

		// Pass 1: lay out the page with real text views, and let SwiftUI settle the baseline grid.
		let hostingView = NSHostingView(rootView: pageView)
		hostingView.frame = frame
		hostingView.appearance = NSAppearance(named: .aqua) // Paper is white, also in dark mode
		let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = hostingView
		for _ in 0..<2 {
			hostingView.layoutSubtreeIfNeeded()
			try? await Task.sleep(for: .milliseconds(40))
		}
		hostingView.displayIfNeeded()
		let textViews = Self.textViews(in: hostingView).map { view -> (MagazineTextNSView, CGRect) in
			var rect = view.convert(view.bounds, to: hostingView)
			if !hostingView.isFlipped {
				rect.origin.y = size.height - rect.maxY
			}
			return (view, rect) // Top-left origin
		}

		// Pass 2: SwiftUI draws the page, text views left empty, then the text views draw themselves.
		let data = NSMutableData()
		var mediaBox = CGRect(origin: .zero, size: size)
		guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
			return nil
		}
		let renderer = ImageRenderer(content: pageView.environment(\.magazineDrawsTextSeparately, true))
		renderer.proposedSize = ProposedViewSize(size)

		NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
			context.beginPDFPage(nil)
			renderer.render { _, render in
				render(context)
			}
			for (view, rect) in textViews {
				context.saveGState()
				// From PDF space (bottom-left origin) into the flipped text view.
				context.translateBy(x: rect.minX, y: size.height - rect.minY)
				context.scaleBy(x: 1, y: -1)
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
				view.draw(view.bounds)
				NSGraphicsContext.restoreGraphicsState()
				context.restoreGState()
			}
			context.endPDFPage()
			context.closePDF()
		}

		window.contentView = nil
		window.close()
		return data as Data
	}

	static func textViews(in view: NSView) -> [MagazineTextNSView] {
		var result = [MagazineTextNSView]()
		for subview in view.subviews {
			if let textView = subview as? MagazineTextNSView {
				result.append(textView)
			}
			result += textViews(in: subview)
		}
		return result
	}

	/// Every article on the page links to its web page.
	func addLinks(for block: MagazineBlock, to page: PDFPage) {
		let origin = CGPoint(x: (Self.pageSize.width - metrics.blockWidth) / 2, y: headHeight + metrics.topMargin)
		for (rect, article) in linkRects(for: block) {
			guard let link = article.preferredLink, let url = URL(string: link) else {
				continue
			}
			// PDF coordinates start at the bottom left.
			let pageRect = CGRect(x: origin.x + rect.minX, y: Self.pageSize.height - (origin.y + rect.maxY), width: rect.width, height: rect.height)
			let annotation = PDFAnnotation(bounds: pageRect, forType: .link, withProperties: nil)
			annotation.url = url
			annotation.border = PDFBorder() // No visible box
			annotation.border?.lineWidth = 0
			page.addAnnotation(annotation)
		}
	}

	/// Rects in block coordinates (top left origin). Briefs share their area in a grid of cells.
	func linkRects(for block: MagazineBlock) -> [(CGRect, Article)] {
		var result = [(CGRect, Article)]()
		for slot in block.slots {
			switch slot {
			case .masthead:
				continue
			case let .module(_, area, item, _, _, _):
				result.append((metrics.frame(for: area), item.article))
			case let .briefs(area, items, columns, title):
				let frame = metrics.frame(for: area)
				let titleHeight = title == nil ? metrics.size(0.012) : metrics.size(0.022) * 1.4 + metrics.size(0.024)
				let rows = Int(ceil(Double(items.count) / Double(columns)))
				let cellWidth = (frame.width - CGFloat(columns - 1) * metrics.columnGap) / CGFloat(columns)
				let cellHeight = (frame.height - titleHeight) / CGFloat(max(rows, 1))
				for (index, item) in items.enumerated() {
					let row = index / columns
					let column = index % columns
					let x = frame.minX + CGFloat(column) * (cellWidth + metrics.columnGap)
					let y = frame.minY + titleHeight + CGFloat(row) * cellHeight
					result.append((CGRect(x: x, y: y, width: cellWidth, height: cellHeight), item.article))
				}
			}
		}
		return result
	}
}

/// One A4 page: running head, the magazine block, page number. Black blocks bleed to the page edge.
struct MagazinePDFPage: View {

	let block: MagazineBlock
	let metrics: MagazineMetrics
	@ObservedObject var model: MagazineModel
	let pageNumber: Int
	let title: String
	let date: String
	let headHeight: CGFloat

	var body: some View {
		let foreground: Color = block.isDark ? Color(white: 0.6) : Color(white: 0.4)
		VStack(spacing: 0) {
			// Running head. The first page has the masthead instead.
			VStack(spacing: 0) {
				Spacer(minLength: 0)
				if pageNumber > 1 {
					HStack {
						Text(title).fontWeight(.semibold)
						Spacer()
						Text(date)
					}
					.font(.system(size: 7.5))
					.foregroundStyle(foreground)
					.padding(.bottom, 4)
					Rectangle().frame(height: 0.5).foregroundStyle(foreground.opacity(0.6))
				}
			}
			.frame(width: metrics.blockWidth, height: headHeight * 0.6)
			.frame(height: headHeight, alignment: .bottom)

			MagazineBlockView(block: block, metrics: metrics, model: model)

			Text("\(pageNumber)")
				.font(.system(size: 8, weight: .medium))
				.foregroundStyle(foreground)
				.frame(width: metrics.blockWidth, alignment: pageNumber.isMultiple(of: 2) ? .leading : .trailing)
				.frame(height: Self.footHeight(headHeight), alignment: .center)
		}
		.frame(width: MagazinePDFExporter.pageSize.width, height: MagazinePDFExporter.pageSize.height)
		.background(block.isDark ? Color.black : Color.white)
		.environment(\.colorScheme, .light)
	}

	static func footHeight(_ headHeight: CGFloat) -> CGFloat {
		MagazinePDFExporter.pageSize.height - headHeight - floor(MagazinePDFExporter.pageSize.width / 0.84)
	}
}
