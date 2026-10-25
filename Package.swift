// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "TextendCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "TextendCore", targets: ["TextendCore"])],
  targets: [
    .target(
      name: "TextendCore", path: "Textend",
      exclude: [
        "App/TextendApp.swift", "App/UpdaterService.swift", "Support", "Views", "Resources",
      ],
      sources: [
        "Core", "Models", "Stores", "Services", "App/AppState.swift",
        "App/EditorDraftBinding.swift",
      ]),
    .testTarget(
      name: "TextendCoreTests", dependencies: ["TextendCore"], path: "Tests/TextendCoreTests"),
    .target(
      name: "TextendLayout", path: "Textend/Support",
      exclude: [
        "LibrarySplitView.swift", "WindowLifecycleView.swift", "ThemedSelectionBridge.swift",
      ],
      sources: ["PinnedContentController.swift", "DockVisibility.swift"]),
    .testTarget(
      name: "TextendLayoutTests", dependencies: ["TextendLayout"], path: "Tests/TextendLayoutTests"),
  ]
)
