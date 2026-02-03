//
//  EmptyStateView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .padding()
            
            Text("No Active Loans")
                .font(.title2)
                .bold()
            
            Text("Create a new agreement to get started.")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    EmptyStateView()
}
