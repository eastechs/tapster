import AppKit

/// Keeps a child controller's internal layout constraints inside its allocated content area.
@MainActor final class PinnedContentController<Content: NSViewController>: NSViewController {
  let content: Content

  init(content: Content) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Use init(content:)") }

  override func loadView() {
    view = NSView()
    addChild(content)
    let childView = content.view
    childView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(childView)
    NSLayoutConstraint.activate([
      childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      childView.topAnchor.constraint(equalTo: view.topAnchor),
      childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
}
