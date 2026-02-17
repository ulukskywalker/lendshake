//
//  HapticUtility.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum HapticUtility {
    #if canImport(UIKit)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    static func selection() {
        #if canImport(UIKit)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare() // Prepare for next call
        #endif
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
        #endif
    }
    
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
