//
//  MediaRSSTests.swift
//  RSParserTests
//
//  Created by Ulf Schuster on 10/22/26.
//

import Foundation
import Testing
import RSParser

@Suite struct MediaRSSTests {

	@Test func rssTakesWidestMediaImage() throws {
		let xml = """
		<?xml version="1.0"?>
		<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
		<channel><title>T</title><link>https://example.com/</link>
		<item>
			<title>Widest wins</title><link>https://example.com/a</link>
			<media:thumbnail url="https://example.com/small.jpg" width="175"/>
			<media:content url="https://example.com/large.jpg" medium="image" width="1920"><media:title>Not the item title</media:title></media:content>
			<media:content url="https://example.com/clip.mp4" medium="video" width="3840"/>
		</item>
		<item>
			<title>Group and enclosure</title><link>https://example.com/b</link>
			<media:group><media:thumbnail url="https://example.com/thumb.jpg"/></media:group>
			<enclosure url="/images/photo.webp" type="image/webp" length="1000"/>
		</item>
		<item>
			<title>Content beats earlier enclosure</title><link>https://example.com/d</link>
			<enclosure url="https://example.com/tiny.jpg" type="image/jpeg" length="0"/>
			<media:content medium="image" url="https://example.com/full.jpg"/>
		</item>
				<item><title>No image</title><link>https://example.com/c</link></item>
		</channel></rss>
		"""
		let feed = try #require(try FeedParser.parse(ParserData(url: "https://example.com/feed", data: Data(xml.utf8))))
		let items = Dictionary(uniqueKeysWithValues: feed.items.map { ($0.title ?? "", $0) })
		#expect(items["Widest wins"]?.imageURL == "https://example.com/large.jpg")
		#expect(items["Widest wins"] != nil, "media:title must not replace the item title")
		#expect(items["Group and enclosure"]?.imageURL == "https://example.com/images/photo.webp")
		#expect(items["No image"]?.imageURL == nil)
		#expect(items["Content beats earlier enclosure"]?.imageURL == "https://example.com/full.jpg")
	}

	@Test func atomTakesMediaThumbnail() throws {
		let xml = """
		<?xml version="1.0" encoding="utf-8"?>
		<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
		<title>T</title><link href="https://example.com/"/><id>urn:t</id><updated>2026-10-22T10:00:00Z</updated>
		<entry>
			<title>Video entry</title><id>urn:e</id><link href="https://example.com/e"/><updated>2026-10-22T10:00:00Z</updated>
			<media:group><media:title>Media title</media:title><media:thumbnail url="https://example.com/hq.jpg" width="480"/></media:group>
		</entry>
		</feed>
		"""
		let feed = try #require(try FeedParser.parse(ParserData(url: "https://example.com/atom", data: Data(xml.utf8))))
		let item = try #require(feed.items.first)
		#expect(item.title == "Video entry")
		#expect(item.imageURL == "https://example.com/hq.jpg")
	}
}

@Suite struct MetaPlusTests {

	@Test func br24ImageFromMetaPlus() throws {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:mp="http://www.tagesschau.de/rss/1.1/modules/metaplus/1.1.1/">
		<channel rdf:about="https://example.com/"><title>T</title><link>https://example.com/</link></channel>
		<item rdf:about="https://example.com/a"><title>BR24 item</title><link>https://example.com/a</link>
			<mp:image><mp:width>996</mp:width><mp:alt>Alt</mp:alt><mp:data>https://img.example.com/big.jpeg?w=996&amp;h=560</mp:data></mp:image>
			<mp:image><mp:width>568</mp:width><mp:data>https://img.example.com/small.jpeg</mp:data></mp:image>
		</item>
		</rdf:RDF>
		"""
		let feed = try #require(try FeedParser.parse(ParserData(url: "https://example.com/rdf", data: Data(xml.utf8))))
		let item = try #require(feed.items.first)
		#expect(item.title == "BR24 item")
		#expect(item.imageURL == "https://img.example.com/big.jpeg?w=996&h=560")
	}
}
