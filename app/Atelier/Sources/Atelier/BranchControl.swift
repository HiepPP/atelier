import SwiftUI

struct BranchControl: View {
    let current: String
    let branches: [String]
    let onSwitch: (String) -> Void

    var body: some View {
        Menu {
            ForEach(branches, id: \.self) { branch in
                Button {
                    onSwitch(branch)
                } label: {
                    if branch == current {
                        Label(branch, systemImage: "checkmark")
                    } else {
                        Text(branch)
                    }
                }
                .disabled(branch == current)
            }
        } label: {
            Label(current.isEmpty ? "Detached HEAD" : current, systemImage: "arrow.triangle.branch")
                .atelierFont(size: 10.5, weight: .medium, design: .monospaced)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .frame(maxWidth: 170, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help(current.isEmpty ? "Detached HEAD" : current)
    }
}
