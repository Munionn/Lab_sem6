import UIKit

final class HapticsService {
    static let shared = HapticsService()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    private init() {
        impactGenerator.prepare()
    }

    func tap() {
        impactGenerator.impactOccurred()
    }
}

