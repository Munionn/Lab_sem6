import SwiftUI

struct Theme: Identifiable, Codable {
    let id: String
    var primaryColor: Color
    var secondaryColor: Color
    var backgroundColor: Color

    static let `default` = Theme(
        id: "default",
        primaryColor: .orange,
        secondaryColor: .gray,
        backgroundColor: Color(.systemBackground)
    )

    var preferredColorScheme: ColorScheme? {
        nil
    }
}

