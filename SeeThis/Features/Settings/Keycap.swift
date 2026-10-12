import SwiftUI

struct Keycap: View {
    let label: String
    let isHighlighted: Bool

    init(_ label: String, isHighlighted: Bool = false) {
        self.label = label
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        Text(label)
            .monospaced()
            .frame(minWidth: 24, minHeight: 22, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .opacity(isHighlighted ? 0.9 : 0.2)
            }
            .shadow(color: Color.accentColor.opacity(isHighlighted ? 0.35 : 0), radius: 3)
    }
}
