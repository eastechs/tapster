// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "TapsterCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "TapsterCore", targets: ["TapsterCore"])],
  targets: [
    .target(
      name: "TapsterCore", path: "Tapster",
      exclude: ["App/TapsterApp.swift", "Support", "Views", "Resources"],
      sources: [
        "Core", "Models", "Stores", "Services", "App/AppState.swift",
        "App/EditorDraftBinding.swift",
      ]),
    .testTarget(
      name: "TapsterCoreTests", dependencies: ["TapsterCore"], path: "Tests/TapsterCoreTests"),
    .target(
      name: "TapsterLayout", path: "Tapster/Support",
      exclude: ["LibrarySplitView.swift", "WindowLifecycleView.swift"],
      sources: ["PinnedContentController.swift"]),
    .testTarget(
      name: "TapsterLayoutTests", dependencies: ["TapsterLayout"], path: "Tests/TapsterLayoutTests"),
  ]
)
