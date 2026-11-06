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
