//
//  CircularAmountDial.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CircularAmountDial: View {
    @Binding var value: Double
    let maxValue: Double
    let tintColor: Color

    // Start the dial at 7 o'clock and map full 360° to 0..maxValue
    private let startAngle = Angle(degrees: 210) // 7 o'clock

    private let dialRadius: CGFloat = 120
    private let handleRadius: CGFloat = 16
    private let trackWidth: CGFloat = 32

    #if canImport(UIKit)
    @State private var hapticGenerator: UISelectionFeedbackGenerator?
    #endif

    private var progress: Double {
        max(0, min(1, value / maxValue))
    }

    var body: some View {
        let handleAngle = Angle(radians: (2 * .pi) * progress) + startAngle

        ZStack {
            // Full background track
            Circle()
                .stroke(Color.gray.opacity(0.15), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .frame(width: dialRadius * 2, height: dialRadius * 2)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(tintColor, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .rotationEffect(startAngle)
                .frame(width: dialRadius * 2, height: dialRadius * 2)

            // Handle knob: rotate first, then offset to revolve around the center
            Circle()
                .fill(Color.white)
                .frame(width: handleRadius * 2, height: handleRadius * 2)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .overlay(Circle().stroke(Color.gray.opacity(0.1), lineWidth: 1))
                .offset(x: dialRadius)
                .rotationEffect(handleAngle)

            // Center text
            VStack {
                Text("Lending")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text(value.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring, value: value)
            }
        }
        .contentShape(Circle().inset(by: -handleRadius))
        .gesture(dragGesture)
        .frame(width: dialRadius * 2 + handleRadius * 2, height: dialRadius * 2 + handleRadius * 2)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                #if canImport(UIKit)
                if self.hapticGenerator == nil {
                    self.hapticGenerator = UISelectionFeedbackGenerator()
                    self.hapticGenerator?.prepare()
                }
                #endif

                let currentProgress = self.value / maxValue
                let touchProgress = progressFrom(location: gesture.location)
                
                // Prevent wrap-around by checking the distance of the jump.
                // If the change is too large (e.g., > 0.5 of the circle), we clamp to the boundaries.
                var finalProgress = touchProgress
                let jumpThreshold = 0.5
                
                if touchProgress - currentProgress > jumpThreshold {
                    // Jumping backwards across the seam (e.g., from 0.1 to 0.9)
                    finalProgress = 0.0
                } else if currentProgress - touchProgress > jumpThreshold {
                    // Jumping forwards across the seam (e.g., from 0.9 to 0.1)
                    finalProgress = 1.0
                }

                let unboundedValue = finalProgress * maxValue
                
                // Snap to increments of 25
                let rounded = (unboundedValue / 25).rounded() * 25
                let clamped = min(max(rounded, 0), maxValue)

                #if canImport(UIKit)
                if abs(self.value - clamped) >= 25 {
                    self.hapticGenerator?.selectionChanged()
                }
                #endif

                self.value = clamped
            }
            .onEnded { _ in
                #if canImport(UIKit)
                self.hapticGenerator = nil
                #endif
            }
    }

    private func progressFrom(location: CGPoint) -> Double {
        // Create a vector from the center of the dial to the touch location.
        let center = CGPoint(x: dialRadius + handleRadius, y: dialRadius + handleRadius)
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)

        // Calculate the angle of the touch vector. atan2 returns a value in the range [-π, π].
        // We normalize this to [0, 2π) to make it easier to work with.
        var touchAngle = atan2(vector.y, vector.x)
        if touchAngle < 0 { touchAngle += 2 * .pi }

        // Calculate the progress by finding the angle relative to the dial's start angle.
        // The result is normalized to a value between 0.0 and 1.0.
        var relativeAngle = touchAngle - startAngle.radians
        if relativeAngle < 0 { relativeAngle += 2 * .pi }

        return relativeAngle / (2 * .pi)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var value: Double = 2500
        var body: some View {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                CircularAmountDial(value: $value, maxValue: 10000, tintColor: .lsPrimary)
            }
        }
    }
    return PreviewWrapper()
}

