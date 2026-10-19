import SwiftUI

struct AppTopBar: View {
    let title: String
    let subtitle: String
    let palette: Palette
    let theme: ThemeMode
    let toggleTheme: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title).fontWeight(.semibold)
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.muted.opacity(0.65))
            Text(subtitle).foregroundStyle(palette.muted).lineLimit(1)
            Spacer()
            Picker("Theme", selection: Binding(get: { theme }, set: { _ in toggleTheme() })) {
                Text("White").tag(ThemeMode.white)
                Text("Black").tag(ThemeMode.black)
            }.pickerStyle(.segmented).frame(width: 116).help("Choose the white or black theme")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 24).frame(height: 52)
        .background(palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Brand.gradient).frame(height: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

enum Brand {
    static let gradient = LinearGradient(colors: [Color(hex: 0x7C5CFF), Color(hex: 0xFF4F8B), Color(hex: 0xFF8A3D)], startPoint: .leading, endPoint: .trailing)
}

struct PillButtonStyle: ButtonStyle {
    let palette: Palette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : palette.text)
            .background(prominent ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(prominent ? Color.clear : palette.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
