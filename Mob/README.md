## Calculator App (iOS, SwiftUI)

This folder contains a modular implementation of the mobile development course project in Swift for iOS.  
The code is organised using a simple Clean Architecture style with `Domain`, `Data`, `Core`, and `Presentation` layers.

The project is split to match the required steps:

- **Step 1** – Basic calculator (logic + SwiftUI UI + MVVM)
- **Step 2** – Platform APIs (haptics + swipe gesture)
- **Step 3** – Cloud fetching (Firebase-ready abstractions for theme + history + push)
- **Step 4** – Pass Key + biometrics (Keychain + LocalAuthentication)

> This repository only contains Swift source files.  
> To run the app you should add these files into an Xcode iOS App project as described below.

---

### 1. Folder structure

- `Mob/App`
  - Entry point SwiftUI app (`CalcProApp.swift`).
- `Mob/Domain`
  - `Models` – calculator, theme, history, auth models.
  - `UseCases` – calculator engine.
- `Mob/Data`
  - `Theme` – theme repository protocol + Firebase implementation stub.
  - `History` – history repository protocol + Firebase implementation stub.
- `Mob/Core/Services`
  - Haptics, theme service, keychain, biometric auth, notifications, Firebase manager.
- `Mob/Presentation/ViewModels`
  - View models for calculator, theme, history, and auth.
- `Mob/Presentation/Views`
  - SwiftUI views: calculator UI, settings, history, pass key setup / unlock, root container.

---

### 2. How to create and run the Xcode project

1. **Create a new iOS App project**
   - Open Xcode → **File → New → Project…**
   - Template: **iOS → App**
   - Interface: **SwiftUI**, Language: **Swift**
   - Name: e.g. `CalcPro`, Bundle ID: `com.yourname.CalcPro`

2. **Copy the sources from this folder**
   - In Finder, open this repo at `Mob/`.
   - In Xcode, right‑click the project root → **Add Files to “YourAppName”…**
   - Add all folders under `Mob` **(App, Domain, Data, Core, Presentation)**.
   - Make sure “Copy items if needed” is checked.

3. **Set the app entry point**
   - Ensure `CalcProApp.swift` is part of the target.
   - Remove the auto‑generated `YourAppNameApp.swift` or adjust to use `RootView()`.

4. **Add app icon and launch screen**
   - In Xcode → `Assets.xcassets`:
     - Drop your 1024×1024 PNG into `AppIcon` (or use an icon generator).
   - Configure launch screen in **Target → General → App Icons and Launch Images**.

5. **Run on simulator**
   - Choose a simulator (e.g. `iPhone 15 Pro`) from the toolbar.
   - Press **Run** (or `Cmd + R`).

6. **Run on real device**
   - Connect your iPhone.
   - Select your device in the scheme selector.
   - In **Signing & Capabilities**, choose your Apple ID team.
   - Press **Run** and trust the developer profile on the device if asked.

7. **Create a production archive**
   - Scheme: **Any iOS Device (arm64)**.
   - **Product → Archive**.
   - Use the Organizer to export for development / Ad Hoc / App Store.

---

### 3. Firebase and cloud features (Step 3)

The code in `Data/Theme`, `Data/History`, and `Core/Services/FirebaseManager.swift` is written to work with Firebase, but all direct imports are guarded with `#if canImport(Firebase)` so the project compiles before you add Firebase.

To fully enable Step 3:

1. Go to the Firebase console and create a project.
2. Add an iOS app with the same bundle ID as in Xcode.
3. Download `GoogleService-Info.plist` and add it to the Xcode project.
4. In Xcode → **File → Add Packages…**, add the Firebase iOS SDK:
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Add at least: `FirebaseAnalytics`, `FirebaseFirestore`, `FirebaseMessaging`.
5. Ensure `FirebaseManager.configure()` is called from `CalcProApp.init()`.

---

### 4. Pass Key + biometrics (Step 4)

- Pass key (PIN) is stored using `KeychainService` in `Core/Services/KeychainService.swift`;
  only a hash is stored, not the plain PIN.
- Biometric authentication is handled by `BiometricAuthService` using `LocalAuthentication`.
- `AuthViewModel` and the SwiftUI views `SetupPassKeyView` and `UnlockView` implement:
  - Initial PIN setup.
  - Unlock with PIN or biometrics.
  - Reset flow guarded by biometrics.

---

### 5. Platform APIs (Step 2)

- Haptic feedback for button taps is implemented via `HapticsService`.
- Swipe gesture to delete last digit is implemented in `CalculatorView` using `DragGesture`.

You can extend this with a Widget target in Xcode if you want bonus points.

