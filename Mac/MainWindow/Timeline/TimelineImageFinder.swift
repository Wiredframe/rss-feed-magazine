//
//  TimelineImageFinder.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import Foundation
import RSParser
import Articles

/// Finds the image to show for an article in the timeline:
/// the image the feed provides, else the first suitable `<img>` in the article’s HTML.
@MainActor final class TimelineImageFinder {

	static let shared = TimelineImageFinder()

	// articleID: the image URL (nil when the article has none), and the feed’s own image link it was found with.
	// A refresh can add that link to an existing article, so it’s part of the key.
	private var cache = [String: (imageLink: String?, url: String?)]()

	func imageURL(for article: Article) -> String? {
		if let cached = cache[article.articleID], cached.imageLink == article.rawImageLink {
			return cached.url
		}
		let url = Self.findImageURL(for: article)
		cache[article.articleID] = (article.rawImageLink, url)
		return url
	}

	static func findImageURL(for article: Article) -> String? {
		if let imageLink = article.imageLink, imageLink.hasPrefix("http") {
			return imageLink
		}
		let baseURL = article.preferredURL
		for html in [article.contentHTML, article.summary] {
			if let html, let url = firstImageURL(in: html, baseURL: baseURL) {
				return url
			}
		}
		return nil
	}

	/// Returns the first image in `html` that looks like content: not a tracking pixel, icon, or emoji.
	nonisolated static func firstImageURL(in html: String, baseURL: URL?) -> String? {
		let s = html as NSString
		var searchLocation = 0

		for _ in 0..<maxTagsToInspect {
			let imgRange = s.range(of: "<img", options: .caseInsensitive, range: NSRange(location: searchLocation, length: s.length - searchLocation))
			if imgRange.location == NSNotFound {
				return nil
			}
			let tagEnd = endOfTag(in: s, from: imgRange.location + imgRange.length)
			let tag = s.substring(with: NSRange(location: imgRange.location, length: tagEnd - imgRange.location))
			if let url = imageURL(fromTag: tag, baseURL: baseURL) {
				return url
			}
			searchLocation = tagEnd
		}

		return nil
	}
}

private extension TimelineImageFinder {

	nonisolated static let maxTagsToInspect = 5
	nonisolated static let minimumDimension = 64
	nonisolated static let preferredSourceWidth = 800

	/// Index just past the `>` that closes the tag, skipping `>` inside quoted attribute values.
	nonisolated static func endOfTag(in s: NSString, from location: Int) -> Int {
		var quote: unichar?
		var i = location
		while i < s.length {
			let ch = s.character(at: i)
			if let q = quote {
				if ch == q {
					quote = nil
				}
			} else if ch == doubleQuote || ch == singleQuote {
				quote = ch
			} else if ch == greaterThan {
				return i + 1
			}
			i += 1
		}
		return s.length
	}

	nonisolated static let doubleQuote = unichar(UInt8(ascii: "\""))
	nonisolated static let singleQuote = unichar(UInt8(ascii: "'"))
	nonisolated static let greaterThan = unichar(UInt8(ascii: ">"))

	nonisolated static func imageURL(fromTag tag: String, baseURL: URL?) -> String? {
		let attributes = attributes(inTag: tag)

		if let width = attributes["width"].flatMap(Int.init), width < minimumDimension {
			return nil
		}
		if let height = attributes["height"].flatMap(Int.init), height < minimumDimension {
			return nil
		}
		if let className = attributes["class"]?.lowercased(), className.contains("emoji") || className.contains("smiley") {
			return nil
		}

		var candidates = [String]()
		if let srcset = attributes["srcset"] ?? attributes["data-srcset"], let url = preferredSource(inSrcset: srcset) {
			candidates.append(url)
		}
		for key in ["src", "data-src", "data-lazy-src"] {
			if let url = attributes[key] {
				candidates.append(url)
			}
		}

		for candidate in candidates {
			if let url = absoluteImageURL(candidate, baseURL: baseURL) {
				return url
			}
		}
		return nil
	}

	nonisolated static func absoluteImageURL(_ s: String, baseURL: URL?) -> String? {
		let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty || trimmed.hasPrefix("data:") {
			return nil
		}
		guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			return nil
		}
		let path = url.path.lowercased()
		if path.contains("/emoji/") || path.hasSuffix(".svg") {
			return nil
		}
		return url.absoluteString
	}

	/// Picks the smallest candidate at least `preferredSourceWidth` wide, else the widest.
	nonisolated static func preferredSource(inSrcset srcset: String) -> String? {
		var best: (url: String, width: Int)?
		var widest: (url: String, width: Int)?

		for candidate in srcset.split(separator: ",") {
			let parts = candidate.split(whereSeparator: \.isWhitespace)
			guard parts.count == 2, parts[1].hasSuffix("w"), let width = Int(parts[1].dropLast()) else {
				continue
			}
			let url = String(parts[0])
			if width > widest?.width ?? 0 {
				widest = (url, width)
			}
			if width >= preferredSourceWidth && width < best?.width ?? Int.max {
				best = (url, width)
			}
		}

		return (best ?? widest)?.url
	}

	/// Attribute names are lowercased. Values are unquoted and have basic entities decoded.
	nonisolated static func attributes(inTag tag: String) -> [String: String] {
		var attributes = [String: String]()
		let scalars = Array(tag.unicodeScalars)
		var i = 4 // Skip "<img"

		func skipWhitespace() {
			while i < scalars.count && CharacterSet.whitespacesAndNewlines.contains(scalars[i]) {
				i += 1
			}
		}

		while i < scalars.count {
			skipWhitespace()
			let nameStart = i
			while i < scalars.count && !CharacterSet.whitespacesAndNewlines.contains(scalars[i]) && !"=>/".unicodeScalars.contains(scalars[i]) {
				i += 1
			}
			if i == nameStart {
				i += 1 // Stray "/" or ">"
				continue
			}
			let name = String(String.UnicodeScalarView(scalars[nameStart..<i])).lowercased()

			skipWhitespace()
			guard i < scalars.count, scalars[i] == "=" else {
				continue // Attribute without a value
			}
			i += 1
			skipWhitespace()

			var value = ""
			if i < scalars.count, scalars[i] == "\"" || scalars[i] == "'" {
				let quote = scalars[i]
				i += 1
				let valueStart = i
				while i < scalars.count && scalars[i] != quote {
					i += 1
				}
				value = String(String.UnicodeScalarView(scalars[valueStart..<min(i, scalars.count)]))
				i += 1
			} else {
				let valueStart = i
				while i < scalars.count && !CharacterSet.whitespacesAndNewlines.contains(scalars[i]) && scalars[i] != ">" {
					i += 1
				}
				value = String(String.UnicodeScalarView(scalars[valueStart..<i]))
			}

			if attributes[name] == nil {
				attributes[name] = decodeBasicEntities(value)
			}
		}

		return attributes
	}

	nonisolated static func decodeBasicEntities(_ s: String) -> String {
		s.decodingHTMLEntities() // Paths can hold any entity, like &#039; for an apostrophe
	}
}
