//
//  ViewStyles.swift
//  lendshake
//
//  Created by Assistant on 2/7/26.
//

import SwiftUI

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
}
