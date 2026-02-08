//
//  ViewStyles.swift
//  lendshake
//
//  Created by Assistant on 2/7/26.
//

import SwiftUI

enum LSToastStyle {
    case success
    case error

    var backgroundColor: Color {
        switch self {
        case .success:
            return Color.green.opacity(0.95)
        case .error:
            return Color.red.opacity(0.95)
        }
    }

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct LSToastModifier: ViewModifier {
    @Binding var message: String?
    let style: LSToastStyle
    let duration: TimeInterval

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: style.icon)
                        Text(message)
                            .font(.caption)
                            .bold()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(style.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { scheduleDismiss() }
                }
            }
            .onChange(of: message) { _, newValue in
                guard newValue != nil else {
                    dismissTask?.cancel()
                    dismissTask = nil
                    return
                }
                scheduleDismiss()
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    message = nil
                }
            }
        }
    }
}

extension View {
    func lsCardContainer() -> some View {
        self
            .background(Color.lsCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.15), lineWidth: 1)
            )
    }

    func lsToast(message: Binding<String?>, style: LSToastStyle, duration: TimeInterval = 3) -> some View {
        modifier(LSToastModifier(message: message, style: style, duration: duration))
    }
}
