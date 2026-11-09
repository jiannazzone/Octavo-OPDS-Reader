import SwiftUI

/// `.secondary`, for words on glass. With Increase Contrast it's still only
/// 4.3 to 4.9:1 there (`docs/notes/accessibility.md`), short of Apple's 4.5, so
/// with that setting on it's `.primary`.
nonisolated struct SecondaryOnGlass: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorSchemeContrast == .increased ? HierarchicalShapeStyle.primary : .secondary
    }
}

extension ShapeStyle where Self == SecondaryOnGlass {
    static var secondaryOnGlass: SecondaryOnGlass { SecondaryOnGlass() }
}

/// The words on a filled button. The accent (decision 31) is pale in Dark Mode,
/// where the system's white on it is only 1.7:1.
nonisolated struct OnAccent: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        guard environment.isEnabled else { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(environment.colorScheme == .dark ? Color.black : Color.white)
    }
}

extension ShapeStyle where Self == OnAccent {
    static var onAccent: OnAccent { OnAccent() }
}

/// Grey or tinted words in a list row that fills with the accent when it's
/// selected (Settings' list on a wide sheet, while the list has the focus):
/// `base` until then, the words on a filled button on the fill. The system
/// turns only plain words white there, and these vanished.
nonisolated struct InSelectableRow<Base: ShapeStyle>: ShapeStyle {
    let base: Base

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.backgroundProminence == .increased ? AnyShapeStyle(OnAccent()) : AnyShapeStyle(base)
    }
}

extension ShapeStyle where Self == InSelectableRow<HierarchicalShapeStyle> {
    static var secondaryInRow: Self { InSelectableRow(base: .secondary) }
}

extension ShapeStyle where Self == InSelectableRow<TintShapeStyle> {
    static var tintInRow: Self { InSelectableRow(base: .tint) }
}
