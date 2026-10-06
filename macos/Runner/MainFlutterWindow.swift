import Cocoa
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  var edgePanel: EdgePanel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    LoginItemChannel.register(with: flutterViewController.engine.binaryMessenger)
    edgePanel = EdgePanel(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

enum LoginItemChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "usage_monitor/login_item", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result("unsupported")
        return
      }
      let service = SMAppService.mainApp
      switch call.method {
      case "status":
        result(statusName(service.status))
      case "setEnabled":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        do {
          if enabled {
            try service.register()
          } else {
            try service.unregister()
          }
          result(statusName(service.status))
        } catch {
          result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(macOS 13.0, *)
  private static func statusName(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    default: return "notRegistered"
    }
  }
}

final class EdgePanel {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var monitors: [Any] = []
  private var dwellTimer: Timer?
  private var leaveTimer: Timer?
  private var outsideSince: Date?
  private var screen: NSScreen?
  private var generation = 0
  private var pinned = false
  private(set) var enabled = false
  private(set) var shown = false
  private let margin: CGFloat = 10
  private let cornerGuard: CGFloat = 30

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "usage_monitor/edge", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "setEnabled":
        self.setEnabled(args["enabled"] as? Bool ?? false)
      case "setPinned":
        self.pinned = args["pinned"] as? Bool ?? false
      case "show":
        self.show(on: self.screenUnderMouse() ?? NSScreen.main)
      case "hide":
        self.hide()
      case "resize":
        self.resize(height: CGFloat(args["height"] as? Double ?? 0))
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  func showFromReopen() {
    show(on: screenUnderMouse() ?? NSScreen.main)
    window?.makeKey()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func setEnabled(_ value: Bool) {
    enabled = value
    if value {
      guard monitors.isEmpty else { return }
      let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
      if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
        self?.pointerMoved()
      }) {
        monitors.append(global)
      }
      if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
        self?.pointerMoved()
        return event
      }) {
        monitors.append(local)
      }
    } else {
      monitors.forEach { NSEvent.removeMonitor($0) }
      monitors.removeAll()
      dwellTimer?.invalidate()
      dwellTimer = nil
      if shown { hide() }
    }
  }

  private func pointerMoved() {
    guard enabled, !shown else { return }
    guard edgeScreen(at: NSEvent.mouseLocation) != nil else {
      dwellTimer?.invalidate()
      dwellTimer = nil
      return
    }
    guard dwellTimer == nil else { return }
    dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
      guard let self else { return }
      self.dwellTimer = nil
      if let target = self.edgeScreen(at: NSEvent.mouseLocation) {
        self.show(on: target)
      }
    }
  }

  private func edgeScreen(at point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { candidate in
      let frame = candidate.frame
      let visible = candidate.visibleFrame
      guard point.x >= frame.maxX - 2, point.x <= frame.maxX + 1,
            point.y >= visible.minY + cornerGuard, point.y <= visible.maxY - cornerGuard else { return false }
      return !NSScreen.screens.contains { other in
        other !== candidate && abs(other.frame.minX - frame.maxX) < 1
          && point.y >= other.frame.minY && point.y <= other.frame.maxY
      }
    }
  }

  private func screenUnderMouse() -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
  }

  private func frame(on target: NSScreen, height: CGFloat) -> NSRect {
    let visible = target.visibleFrame
    let width = window?.frame.width ?? 380
    let clamped = min(height, visible.height - margin * 2)
    return NSRect(x: visible.maxX - width - margin, y: visible.midY - clamped / 2, width: width, height: clamped)
  }

  private func show(on target: NSScreen?) {
    guard let window, let target else { return }
    generation += 1
    screen = target
    let end = frame(on: target, height: window.frame.height)
    if !shown {
      var start = end
      start.origin.x = target.frame.maxX + 2
      window.setFrame(start, display: false)
      window.alphaValue = 0
    }
    window.level = .floating
    window.orderFrontRegardless()
    shown = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().setFrame(end, display: true)
      window.animator().alphaValue = 1
    }
    outsideSince = nil
    leaveTimer?.invalidate()
    leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.checkPointerLeft()
    }
    channel.invokeMethod("shown", arguments: nil)
  }

  private func checkPointerLeft() {
    guard let window, shown else { return }
    if pinned || window.isKeyWindow {
      outsideSince = nil
      return
    }
    let point = NSEvent.mouseLocation
    let near = window.frame.insetBy(dx: -20, dy: -20).contains(point)
    if near || (screen != nil && edgeScreen(at: point) === screen) {
      outsideSince = nil
      return
    }
    let since = outsideSince ?? Date()
    outsideSince = since
    if Date().timeIntervalSince(since) > 0.35 { hide() }
  }

  private func hide() {
    guard let window, shown else { return }
    shown = false
    leaveTimer?.invalidate()
    leaveTimer = nil
    generation += 1
    let current = generation
    var end = window.frame
    end.origin.x = (screen?.frame.maxX ?? end.maxX) + 2
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().setFrame(end, display: true)
      window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      guard let self, self.generation == current else { return }
      window.orderOut(nil)
      window.alphaValue = 1
      window.level = .normal
    })
    channel.invokeMethod("hidden", arguments: nil)
  }

  private func resize(height: CGFloat) {
    guard let window, height > 0 else { return }
    if shown, let target = screen {
      window.setFrame(frame(on: target, height: height), display: true)
    } else {
      var frame = window.frame
      frame.origin.y += frame.height - height
      frame.size.height = height
      window.setFrame(frame, display: false)
    }
  }
}
