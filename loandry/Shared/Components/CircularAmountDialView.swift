//
//  CircularAmountDial.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import SwiftUI

struct CircularAmountDialView: View {
    @Binding var value: Double
    let maxValue: Double
    let tintColor: Color
    
    // UI Constants
    private let startAngle = Angle(degrees: 210) // 7 o'clock
    private let dialRadius: CGFloat = 120
    private let handleRadius: CGFloat = 16
    private let trackWidth: CGFloat = 32
    
    private var progress: Double {
        max(0, min(1, value / maxValue))
    }
    
    private var handleAngle: Angle {
        Angle(radians: (2 * .pi) * progress) + startAngle
    }

    var body: some View {
        ZStack {
            // Background Track
            Circle()
                .stroke(Color.gray.opacity(0.15), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .frame(width: dialRadius * 2, height: dialRadius * 2)

            // Progress Arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(tintColor, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                .rotationEffect(startAngle)
                .frame(width: dialRadius * 2, height: dialRadius * 2)

            // Handle Knob
            Circle()
                .fill(Color.white)
                .frame(width: handleRadius * 2, height: handleRadius * 2)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .overlay(Circle().stroke(Color.gray.opacity(0.1), lineWidth: 1))
                .offset(x: dialRadius)
                .rotationEffect(handleAngle)

            // Center Content
            VStack {
                Text("Lending")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text(CurrencyUtility.formatUSD(value))
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
                updateValue(from: gesture.location)
            }
    }
    
    private func updateValue(from location: CGPoint) {
        let touchProgress = progressFrom(location: location)
        
        // Prevent wrap-around logic
        let jumpThreshold = 0.5
        var finalProgress = touchProgress
        
        if touchProgress - progress > jumpThreshold {
            finalProgress = 0.0
        } else if progress - touchProgress > jumpThreshold {
            finalProgress = 1.0
        }
        
        let unboundedValue = finalProgress * maxValue
        
        // Snap to increments of 25
        let rounded = (unboundedValue / 25).rounded() * 25
        let clamped = min(max(rounded, 0), maxValue)
        
        if abs(self.value - clamped) >= 25 {
            HapticUtility.selection()
        }
        
        self.value = clamped
    }
    
    private func progressFrom(location: CGPoint) -> Double {
        let center = CGPoint(x: dialRadius + handleRadius, y: dialRadius + handleRadius)
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)

        var touchAngle = atan2(vector.y, vector.x)
        if touchAngle < 0 { touchAngle += 2 * .pi }

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
                Color.appBackground.ignoresSafeArea()
                CircularAmountDialView(value: $value, maxValue: 10000, tintColor: .blue)
            }
        }
    }
    return PreviewWrapper()
}
