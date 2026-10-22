//
//  TimelineLayout.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/19/26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation

/// Standard: one custom-drawn column, article view to the right.
/// Column: multi-column table with a header, article view below, like Mail’s Use Column Layout.
/// Magazine: no timeline or article view, but one horizontally scrolling surface laid out like a magazine.
enum TimelineLayout {
	case standard
	case column
	case magazine
}

extension AppDefaults {

	var timelineLayout: TimelineLayout {
		if useMagazineLayout {
			return .magazine
		}
		return useColumnLayout ? .column : .standard
	}
}
