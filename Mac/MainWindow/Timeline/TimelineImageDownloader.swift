//
//  TimelineImageDownloader.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers
import RSCore
import RSWeb

extension Notification.Name {
	static let timelineImageDidBecomeAvailable = Notification.Name("TimelineImageDidBecomeAvailable") // userInfo key: "url"
}

/// Downloads article images for the timeline, scaled down to timeline size.
/// Separate from ImageDownloader, which scales everything to icon size.
///
/// Only images for rows that were actually displayed are fetched. Memory use is capped by
/// `memoryCacheLimit` and disk use by `diskCacheLimit`; on disk the oldest images go first.
/// CacheCleaner also deletes the whole folder every few days.
@MainActor final class TimelineImageDownloader {

	static let shared = TimelineImageDownloader()
	static let cacheFolderName = "TimelineImages"

	private let diskCache = BinaryDiskCache(folder: AppConfig.cacheSubfolder(named: cacheFolderName).path)
	private let memoryCache = NSCache<NSString, NSImage>()
	private var urlsInProgress = Set<String>()
	private var failures = [String: Date]() // url: when to try again; distantFuture when retrying won’t help
	private static let retryInterval: TimeInterval = 60

	// Not Downloader.shared: it allows one connection per host and also fetches feeds, so a timeline
	// or magazine full of images from one host would queue up until requests time out.
	private let urlSession: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpMaximumConnectionsPerHost = 4
		configuration.timeoutIntervalForRequest = 30
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.urlCache = nil
		return URLSession(configuration: configuration)
	}()

	nonisolated private static let maxPixelSize = 960 // Sharp at 2x in a timeline up to 480 points wide
	nonisolated private static let jpegQuality = 0.7
	private static let memoryCacheLimit = 64 * 1024 * 1024 // Bytes of decoded pixels
	nonisolated private static let diskCacheLimit = 200 * 1024 * 1024
	private static let writesBetweenDiskCacheTrims = 100
	private var writesSinceDiskCacheTrim = 0
	private static let maxConcurrentDownloads = 8
	private var activeDownloads = 0
	private var pendingURLs = [String]()

	init() {
		memoryCache.totalCostLimit = Self.memoryCacheLimit
		Self.trimDiskCache(diskCache.folder)
	}

	/// True when the image can’t be loaded and won’t be tried again.
	func hasFailed(_ url: String) -> Bool {
		failures[url] == .distantFuture
	}

	/// The image if it’s in memory. Doesn’t start a fetch.
	func cachedImage(for url: String) -> NSImage? {
		memoryCache.object(forKey: url as NSString)
	}

	/// Waits for the image, up to `timeout`. Returns nil if it can’t be loaded.
	func loadImage(_ url: String, timeout: Duration = .seconds(10)) async -> NSImage? {
		if let image = image(for: url) {
			return image
		}
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(100))
			if let image = cachedImage(for: url) {
				return image
			}
			if !urlsInProgress.contains(url) {
				return nil // Failed
			}
		}
		return nil
	}

	/// Returns the image if in memory, else starts a disk-then-network fetch and returns nil.
	/// Posts timelineImageDidBecomeAvailable when the image arrives.
	func image(for url: String) -> NSImage? {
		if let image = memoryCache.object(forKey: url as NSString) {
			return image
		}
		if urlsInProgress.contains(url) {
			return nil
		}
		if let retryDate = failures[url] {
			if retryDate > Date() {
				return nil
			}
			failures[url] = nil
		}
		urlsInProgress.insert(url)
		Task {
			await fetchImage(url)
		}
		return nil
	}
}

private extension TimelineImageDownloader {

	func fetchImage(_ url: String) async {
		let key = url.md5String
		let diskCache = self.diskCache

		if let data = await Self.readData(diskCache, key), let image = NSImage(data: data) {
			imageDidLoad(url, image)
			return
		}

		// Visible cells ask for their images all at once. Keep the number of
		// simultaneous downloads small and serve the most recent requests first,
		// since those are the rows the user is looking at now.
		if activeDownloads >= Self.maxConcurrentDownloads {
			pendingURLs.append(url)
			return
		}
		await download(url, key: key)
	}

	func download(_ url: String, key: String) async {
		activeDownloads += 1
		defer {
			activeDownloads -= 1
			startNextPendingDownload()
		}

		guard let imageURL = URL(string: url) else {
			didFail(url, retry: false)
			return
		}
		var request = URLRequest(url: imageURL)
		request.setValue(UserAgent.browserUserAgent, forHTTPHeaderField: HTTPRequestHeader.userAgent)

		let data: Data
		do {
			let (responseData, response) = try await urlSession.data(for: request)
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
			guard (200...299).contains(statusCode), !responseData.isEmpty else {
				didFail(url, retry: statusCode >= 500 || statusCode == 429)
				return
			}
			data = responseData
		} catch {
			didFail(url, retry: true) // Timeouts, no network
			return
		}

		guard let scaledData = await Self.scaledImageData(data), let image = NSImage(data: scaledData) else {
			didFail(url, retry: false)
			return
		}

		imageDidLoad(url, image)
		Self.writeData(diskCache, key, scaledData)

		writesSinceDiskCacheTrim += 1
		if writesSinceDiskCacheTrim >= Self.writesBetweenDiskCacheTrims {
			writesSinceDiskCacheTrim = 0
			Self.trimDiskCache(diskCache.folder)
		}
	}

	func didFail(_ url: String, retry: Bool) {
		failures[url] = retry ? Date().addingTimeInterval(Self.retryInterval) : .distantFuture
		urlsInProgress.remove(url)
		if !retry {
			NotificationCenter.default.post(name: .timelineImageDidBecomeAvailable, object: self, userInfo: ["url": url]) // So views stop waiting
		}
	}

	func startNextPendingDownload() {
		guard let url = pendingURLs.popLast() else {
			return
		}
		Task {
			await download(url, key: url.md5String)
		}
	}

	func imageDidLoad(_ url: String, _ image: NSImage) {
		let pixelCount = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
		memoryCache.setObject(image, forKey: url as NSString, cost: pixelCount * 4)
		urlsInProgress.remove(url)
		NotificationCenter.default.post(name: .timelineImageDidBecomeAvailable, object: self, userInfo: ["url": url])
	}

	@concurrent nonisolated static func readData(_ diskCache: BinaryDiskCache, _ key: String) async -> Data? {
		guard let data = diskCache[key], !data.isEmpty else {
			return nil
		}
		return data
	}

	/// Deletes the least recently modified files until the folder is under diskCacheLimit.
	nonisolated static func trimDiskCache(_ folder: String) {
		Task.detached(priority: .background) {
			let folderURL = URL(fileURLWithPath: folder, isDirectory: true)
			let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
			guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: keys) else {
				return
			}

			var files = [(url: URL, date: Date, size: Int)]()
			var totalSize = 0
			for fileURL in fileURLs {
				guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
					continue
				}
				let size = values.totalFileAllocatedSize ?? 0
				files.append((fileURL, values.contentModificationDate ?? .distantPast, size))
				totalSize += size
			}
			if totalSize <= diskCacheLimit {
				return
			}

			for file in files.sorted(by: { $0.date < $1.date }) {
				try? FileManager.default.removeItem(at: file.url)
				totalSize -= file.size
				if totalSize <= diskCacheLimit * 3 / 4 {
					break
				}
			}
		}
	}

	nonisolated static func writeData(_ diskCache: BinaryDiskCache, _ key: String, _ data: Data) {
		Task.detached(priority: .utility) {
			diskCache[key] = data
		}
	}

	/// JPEG data (PNG when the image has transparency) no larger than maxPixelSize on the long side.
	/// Returns nil if the data isn’t an image.
	@concurrent nonisolated static func scaledImageData(_ data: Data) async -> Data? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
			return nil
		}
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
		]
		guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
			return nil
		}
		let opaqueAlphaInfos: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
		let type = opaqueAlphaInfos.contains(cgImage.alphaInfo) ? UTType.jpeg : UTType.png
		guard let mutableData = CFDataCreateMutable(nil, 0),
			  let destination = CGImageDestinationCreateWithData(mutableData, type.identifier as CFString, 1, nil) else {
			return nil
		}
		let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
		CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
		guard CGImageDestinationFinalize(destination) else {
			return nil
		}
		return mutableData as Data
	}
}
