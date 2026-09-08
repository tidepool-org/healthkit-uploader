// swift-tools-version: 5.9
import PackageDescription

// Swift Package manifest for TPHealthKitUploader. This makes the uploader
// dual-mode (CocoaPod via TPHealthKitUploader.podspec *and* SPM via this file),
// mirroring how TidepoolKit, TidepoolAndroidAuth, and TidepoolKotlinAPI are kept
// consumable both ways. CocoaPods ignores this file; SPM ignores the podspec.
//
// The app still consumes the uploader as a CocoaPod today (React Native 0.83's
// iOS build is CocoaPods-based), so nothing changes for the current build. This
// manifest is the enabling step for an eventual SPM cutover: once the app pulls
// the uploader (and, through it, TidepoolKit) via SPM and drops both `pod` lines
// from the Podfile, TidepoolKit no longer needs its podspec.
let package = Package(
    name: "TPHealthKitUploader",
    // 15.1 matches the app and satisfies TidepoolKit's iOS 15.1 floor (the
    // podspec's 15.0 predates that dependency requirement).
    platforms: [.iOS("15.1")],
    products: [
        .library(
            name: "TPHealthKitUploader",
            targets: ["TPHealthKitUploader"]),
    ],
    dependencies: [
        // Sibling package in the monorepo, mirroring the CocoaPods
        // `:path => '../../TidepoolKit'` integration relative to the app's ios/.
        .package(path: "../TidepoolKit"),
    ],
    targets: [
        .target(
            name: "TPHealthKitUploader",
            dependencies: ["TidepoolKit"],
            // The pure-Swift sources live under Source/ (SPM recurses into the
            // HealthKit/, Service/, Settings/, Extensions/, Misc/, ThirdParty/
            // subdirectories automatically). The module name stays
            // "TPHealthKitUploader" so `import TPHealthKitUploader` in the app's
            // native module is unchanged.
            path: "Source",
            // Carry-overs from the CocoaPods framework layout that have no place
            // in an SPM target: the umbrella header and the framework Info.plist.
            exclude: [
                "TPHealthKitUploader.h",
                "Info.plist",
            ]),
    ]
)
