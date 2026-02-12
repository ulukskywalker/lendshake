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
    func lsAuthInput() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
            )
    }

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

    func lsPrimaryButton(background: Color = .lsPrimary) -> some View {
        self
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(background.opacity(0.15), lineWidth: 1)
            )
    }

    func lsSecondaryButton() -> some View {
        self
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
            )
    }

    func lsDestructiveButton() -> some View {
        self
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(.red)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
    }
}
