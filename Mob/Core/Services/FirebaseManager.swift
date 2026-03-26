import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum FirebaseManager {
    static func configureIfAvailable() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
    }
}


