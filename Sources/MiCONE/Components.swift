import AppKit
import SwiftUI

enum Brand {
    /// Bleu du logo : la lettre « i » de MiCONE.
    static let color = Color(red: 0x40 / 255, green: 0x90 / 255, blue: 0xf0 / 255)
    static let nsColor = NSColor(srgbRed: 0x40 / 255, green: 0x90 / 255, blue: 0xf0 / 255, alpha: 1)
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(branded: text).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true) }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted).frame(maxWidth: .infinity, alignment: .leading) }
}

struct Check: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true) }
            .toggleStyle(.checkbox).tint(Socle.C.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bouton d'icône de barre d'en-tête (symbole SF), fond de survol Socle.
struct BarButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) { BarGlyph(symbol: symbol, hover: hover) }
            .buttonStyle(.plain).onHover { hover = $0 }.help(help).accessibilityLabel(help)
    }
}

struct BarGlyph: View {
    let symbol: String
    var hover = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            .foregroundStyle(hover ? Socle.C.textStrong : Socle.C.textMuted)
            .frame(width: Socle.M.sizeControl, height: Socle.M.sizeControl)
            .background(hover ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .contentShape(Rectangle())
    }
}

/// Liste déroulante Socle : champ creux, texte fort, chevron.
struct SocleMenuPicker<V: Hashable>: View {
    let options: [(value: V, label: String)]
    @Binding var selection: V
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = options[i].value } label: {
                    if options[i].value == selection { Label(options[i].label, systemImage: "checkmark") } else { Text(options[i].label) }
                }
            }
        } label: {
            HStack(spacing: Socle.M.space2) {
                Text(options.first { $0.value == selection }?.label ?? "").socle(Socle.T.body).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Socle.C.textMuted)
            }
            .padding(.horizontal, Socle.M.space3)
            .frame(maxWidth: .infinity, minHeight: Socle.M.sizeControlLg, alignment: .leading)
            .background(Socle.C.bgSunken)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

struct Panel<Content: View>: View {
    var raised = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(raised ? Socle.C.surfaceRaised : Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }
}

/// Curseur Socle : libellé, valeur en mono, rail fin.
struct SocleSlider: View {
    let label: String
    let valueText: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        VStack(spacing: Socle.M.space1) {
            HStack {
                Text(label).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                Spacer()
                Text(valueText).socle(Socle.T.mono).foregroundStyle(Socle.C.textMuted)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: Double(range.lowerBound)...Double(range.upperBound))
                .tint(Socle.C.accent).controlSize(.small)
        }
    }
}
