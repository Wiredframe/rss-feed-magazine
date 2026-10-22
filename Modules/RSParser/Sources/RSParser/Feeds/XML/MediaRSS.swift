//
//  MediaRSS.swift
//  RSParser
//
//  Created by Ulf Schuster on 10/22/26.
//

/// Images from the Media RSS namespace (http://search.yahoo.com/mrss/), shared by the RSS and Atom parsers.
/// Many feeds put their article image only here, often in a much higher resolution than in the HTML.
enum MediaRSS {

	static func addImage(localName: ArraySlice<UInt8>, attributes: [String: String], to item: RSSItem, resolve: (String) -> String) {
		let isThumbnail = localName.equals("thumbnail")
		guard isThumbnail || localName.equals("content"), let url = attributes["url"], !url.isEmpty else {
			return
		}
		if !isThumbnail && !isImage(attributes: attributes, url: url) {
			return // Video or audio
		}
		let width = attributes["width"].flatMap { Int($0) }
		item.addImageCandidate(url: resolve(url), width: width, isThumbnail: isThumbnail)
	}
}

private extension MediaRSS {

	static let imageExtensions = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".heic"]

	static func isImage(attributes: [String: String], url: String) -> Bool {
		if let medium = attributes["medium"] {
			return medium == "image"
		}
		if let type = attributes["type"] {
			return type.hasPrefix("image/")
		}
		let path = url.lowercased().split(separator: "?").first.map(String.init) ?? ""
		return imageExtensions.contains { path.hasSuffix($0) }
	}
}
