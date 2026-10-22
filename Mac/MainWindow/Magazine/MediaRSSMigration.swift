//
//  MediaRSSMigration.swift
//  NetNewsWire
//
//  Created by Ulf Schuster on 10/22/26.
//  Copyright © 2026 Ulf Schuster. All rights reserved.
//

import Foundation
import Account

/// The parser now reads article images from Media RSS, image enclosures, and ARD metaplus.
/// Feeds that haven’t changed since they were last read are skipped by content hash and
/// conditional GET, and recently checked ones by time, so their articles would get images only when
/// new content arrives. This forgets all that once, so the next refresh reads every feed again.
@MainActor enum MediaRSSMigration {

	private static let defaultsKey = "didResetFeedHashesForArticleImages2"

	static func runIfNeeded() {
		guard !UserDefaults.standard.bool(forKey: defaultsKey) else {
			return
		}
		for account in AccountManager.shared.activeAccounts {
			for feed in account.flattenedFeeds() {
				feed.contentHash = nil
				feed.conditionalGetInfo = nil
				feed.cacheControlInfo = nil
				feed.lastCheckDate = nil // Or a feed read in the last few minutes would be skipped
			}
		}
		UserDefaults.standard.set(true, forKey: defaultsKey)
	}
}
