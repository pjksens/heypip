import AppKit
import Combine
import SwiftUI

// The island lives around the MacBook notch (or as a pill at the top of a screen without one).
// Collapsed: a black band around the notch. Hover: it opens. A new agent note: it peeks for 8 s.
// In the menu bar (a setting): Pip is a menu bar icon; a click opens the same island under it, and notes peek there.
//
// The window never changes size: it is as big as the open island and lets clicks through everywhere except on the
// island. Hover is decided by comparing the pointer with the island's current rectangle, on every mouse move anywhere
// on screen and every time the island changes size, so the island opening can never look like the pointer leaving.

enum IslandMode { case collapsed, peek, expanded }
enum IslandTab { case live, notes }

struct NotchGeometry {
  let screen: NSScreen
  let hasNotch: Bool
  let notchWidth: CGFloat
  let height: CGFloat
  let centerX: CGFloat

  static func detect() -> NotchGeometry {
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
      return NotchGeometry(screen: screen, hasNotch: true, notchWidth: r.minX - l.maxX, height: screen.safeAreaInsets.top,
                           // the two areas are already in global coordinates: adding the screen's origin again put the
                           // island off screen whenever the notched screen was not the main one (second display as main)
                           centerX: (l.maxX + r.minX) / 2)
    }
    return NotchGeometry(screen: screen, hasNotch: false, notchWidth: 120, height: 30, centerX: screen.frame.midX)
  }
}

@MainActor final class IslandState: ObservableObject {
  @Published var mode: IslandMode = .collapsed
  @Published var tab: IslandTab = .live
  @Published var pinned = false
  @Published var languages: [Locale] = []
  /// A printed Pip on the left of the notch while no meeting runs, so people know where Pip lives.
  @Published var restingPip = Store.restingPip { didSet { Store.restingPip = restingPip } }
  /// Pip lives in the menu bar instead of around the notch.
  @Published var inMenuBar = Store.inMenuBar { didSet { Store.inMenuBar = inMenuBar } }
  /// Measured again whenever the screens change (a display plugged in, unplugged, made main, the lid opened or
  /// closed): screen coordinates move with the main display, so a geometry kept from launch puts the island in the
  /// wrong place, often floating in the middle of another screen.
  @Published private(set) var geometry = NotchGeometry.detect()
  func redetect() { geometry = NotchGeometry.detect() }
  let agentName = UserDefaults.standard.string(forKey: "agentName") ?? "Claude"

  static let openWidth: CGFloat = 600
  static let openBody: CGFloat = 290
  /// Width of the ear that holds the printed Pip at rest.
  static let restingEar: CGFloat = 38

  var panelSize: CGSize { CGSize(width: Self.openWidth + 40, height: band + Self.openBody + 30) }

  /// Height of the island's top bar: the notch's height, or a little more under the menu bar.
  var band: CGFloat { inMenuBar ? 40 : geometry.height }
  /// Room above a peeking note: it comes out from under the notch, or sits just under the menu bar.
  var peekTop: CGFloat { inMenuBar ? 12 : geometry.height - 6 }
  /// The gap the notch leaves in the top bar.
  var notchGap: CGFloat { inMenuBar ? 0 : geometry.notchWidth }

  func size(for mode: IslandMode, running: Bool) -> CGSize {
    let g = geometry
    if inMenuBar, mode == .collapsed { return .zero }  // nothing on screen: the menu bar icon stands for Pip
    switch mode {
    // at rest: the notch, plus the printed Pip on its left if wanted; while listening: ears on each side for Pip and the timer
    case .collapsed: return CGSize(width: g.notchWidth + (running ? 2 * 64 : (restingPip ? Self.restingEar : 0)), height: g.height)
    case .peek: return CGSize(width: max(g.notchWidth + 200, 460), height: peekTop + 68)
    case .expanded: return CGSize(width: Self.openWidth, height: band + Self.openBody)
    }
  }

  /// The island is centred on the notch, except at rest with the printed Pip: it only grows to the left.
  func shift(for mode: IslandMode, running: Bool) -> CGFloat {
    mode == .collapsed && !running && restingPip && !inMenuBar ? -Self.restingEar / 2 : 0
  }
}

/// The window that holds the island: borderless, above the menu bar, on every Space and over full-screen apps.
/// It can take keyboard focus (the meeting name field) without bringing Pip to the front.
final class NotchPanel: NSPanel {
  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isMovable = false
    hidesOnDeactivate = false
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = true  // until the pointer is on the island
  }

  override var canBecomeKey: Bool { true }
}

@MainActor final class IslandController {
  let meeting: Meeting
  let updater: Updater
  let state = IslandState()
  private let panel = NotchPanel()
  private var bag = Set<AnyCancellable>()
  private var pointerMonitors: [Any] = []
  private var hovering = false
  private var openedByHover = false
  private var closing: Task<Void, Never>?
  private var outsideClick: Any?
  private var statusItem: NSStatusItem?
  private var statusTarget: StatusTarget?
  private var statusMood: PipMood?
  private var statusClock: Timer?

  /// Room around the island that still counts as being on it, in points.
  private static let margin: CGFloat = 4
  /// How long the pointer can be off the island before it closes.
  private static let closeDelay: Duration = .milliseconds(450)

  init(meeting: Meeting, updater: Updater) {
    self.meeting = meeting
    self.updater = updater
    panel.contentView = NSHostingView(rootView: IslandView(meeting: meeting, state: state, updater: updater, onTapIsland: { [weak self] in self?.tapIsland() }))
    placePanel()
    panel.orderFrontRegardless()
    if CommandLine.arguments.contains("--pin") { pin() }  // keeps the island open (screenshots)

    meeting.$peek.receive(on: RunLoop.main).sink { [weak self] peek in
      guard let self else { return }
      if peek != nil, self.state.mode == .collapsed {
        if self.state.inMenuBar { self.placePanel() }
        self.set(.peek)
      }
      if peek == nil, self.state.mode == .peek { self.set(.collapsed) }
    }.store(in: &bag)

    // The island can grow or shrink under a pointer that does not move: look again.
    state.$mode.combineLatest(meeting.$running, state.$restingPip).receive(on: RunLoop.main).sink { [weak self] _ in
      self?.followPointer()
    }.store(in: &bag)

    // Screens plugged, unplugged or rearranged, or the Mac waking up: find the notch again and move there. macOS
    // can send the change before the new layout settles, so look again a moment later.
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.screensChanged() }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.screensChanged() }
    }
    // Notch or menu bar: switching from the settings moves Pip right away.
    state.$inMenuBar.dropFirst().receive(on: RunLoop.main).sink { [weak self] inMenuBar in
      self?.applyPlacement(show: inMenuBar)
    }.store(in: &bag)
    // The menu bar icon shows Pip's mood.
    meeting.objectWillChange.debounce(for: .milliseconds(80), scheduler: RunLoop.main).sink { [weak self] in
      self?.refreshStatusIcon()
      self?.refreshStatusClock()
    }.store(in: &bag)

    watchPointer()
    applyPlacement(show: false)
  }

  private func screensChanged() {
    state.redetect()
    placePanel()
    followPointer()
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard let self else { return }
      self.state.redetect()
      self.placePanel()
      self.followPointer()
    }
  }

  private func placePanel() {
    let s = state.panelSize
    if state.inMenuBar, let window = statusItem?.button?.window, let screen = window.screen {
      // hang the island under the menu bar icon, kept on screen
      let item = window.frame
      let x = min(max(item.midX - s.width / 2, screen.frame.minX), screen.frame.maxX - s.width)
      panel.setFrame(NSRect(x: x, y: item.minY - 4 - s.height, width: s.width, height: s.height), display: true)
      return
    }
    let g = state.geometry
    panel.setFrame(NSRect(x: g.centerX - s.width / 2, y: g.screen.frame.maxY - s.height, width: s.width, height: s.height), display: true)
  }

  /// Puts Pip around the notch or in the menu bar. `show` opens the island under the new icon, so people see where
  /// Pip went.
  private func applyPlacement(show: Bool) {
    if state.pinned { unpin() }
    set(.collapsed)
    if state.inMenuBar {
      if statusItem == nil {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let target = StatusTarget { [weak self] in self?.statusItemClicked() }
        item.button?.target = target
        item.button?.action = #selector(StatusTarget.fire)
        item.button?.toolTip = "Pip"
        statusItem = item
        statusTarget = target
        statusMood = nil
        refreshStatusIcon()
      }
    } else if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      statusTarget = nil
    }
    refreshStatusClock()
    // the icon has a place on screen only after the menu bar lays it out
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.placePanel()
      if show { self.pin() }
    }
  }

  private func statusItemClicked() {
    if state.mode == .expanded { unpin(); set(meeting.peek != nil ? .peek : .collapsed) } else { pin() }
  }

  private func refreshStatusIcon() {
    guard let button = statusItem?.button else { return }
    let mood = meeting.mood
    guard mood != statusMood else { return }
    statusMood = mood
    // on a white disc: a blue Pip alone can vanish on some wallpapers
    let icon = ZStack {
      Circle().fill(Color.white)
      Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5)
      Pip(mood: mood, size: 14).offset(y: 0.5)
    }
    .frame(width: 20, height: 20)
    .padding(1)
    let r = ImageRenderer(content: icon)
    r.scale = NSScreen.main?.backingScaleFactor ?? 2
    button.image = r.nsImage
  }

  /// While recording, the recording time next to the icon (the notch shows it in its right ear).
  private func refreshStatusClock() {
    guard let button = statusItem?.button, meeting.running else {
      statusItem?.button?.title = ""
      statusClock?.invalidate()
      statusClock = nil
      return
    }
    let t = Int(meeting.elapsed(at: Date()))
    button.imagePosition = .imageLeading
    button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    button.title = t >= 3600 ? String(format: " %d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: " %d:%02d", t / 60, t % 60)
    if statusClock == nil {
      statusClock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshStatusClock() }
      }
    }
  }

  func set(_ mode: IslandMode) {
    guard state.mode != mode else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.mode = mode }
    if mode == .expanded { panel.makeKey() }
  }

  /// The island's rectangle on screen, as it is drawn right now.
  private func islandRect() -> NSRect {
    let size = state.size(for: state.mode, running: meeting.running)
    let f = panel.frame
    let x = f.midX - size.width / 2 + state.shift(for: state.mode, running: meeting.running)
    return NSRect(x: x, y: f.maxY - size.height, width: size.width, height: size.height)
  }

  /// Mouse moves over other apps reach the global monitor; over Pip's own window, the local one.
  private func watchPointer() {
    let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
    if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
      MainActor.assumeIsolated { self?.followPointer() }
    }) { pointerMonitors.append(m) }
    if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
      MainActor.assumeIsolated { self?.followPointer() }
      return event
    }) { pointerMonitors.append(m) }
    followPointer()
  }

  /// The pointer decides everything: the window takes clicks only while the pointer is on the island, and hovering
  /// the island opens it.
  private func followPointer() {
    let r = islandRect()
    let zone = NSRect(x: r.minX - Self.margin, y: r.minY - Self.margin, width: r.width + 2 * Self.margin, height: r.height + 2 * Self.margin)
    // in the menu bar, nothing is on screen at rest: only the icon opens Pip
    let onIsland = !(state.inMenuBar && state.mode == .collapsed) && zone.contains(NSEvent.mouseLocation)
    if panel.ignoresMouseEvents == onIsland { panel.ignoresMouseEvents = !onIsland }
    guard onIsland != hovering else { return }
    hovering = onIsland
    if onIsland { pointerArrived() } else { pointerWentAway() }
  }

  private func pointerArrived() {
    closing?.cancel()
    closing = nil
    guard state.mode != .expanded else { return }
    openedByHover = true
    set(.expanded)
  }

  private func pointerWentAway() {
    guard state.mode == .expanded, openedByHover, !state.pinned else { return }
    closing = Task { [weak self] in
      try? await Task.sleep(for: Self.closeDelay)
      guard let self, !Task.isCancelled, !self.hovering, !self.state.pinned else { return }
      self.set(self.meeting.peek != nil ? .peek : .collapsed)
    }
  }

  /// Click on the island: keep it open until a click outside it.
  private func tapIsland() {
    if !state.pinned { pin() }
  }

  func pin() {
    if state.inMenuBar { placePanel() }  // the icon may have moved
    state.pinned = true
    openedByHover = false
    set(.expanded)
    if outsideClick == nil {
      outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        Task { @MainActor in self?.unpin() }
      }
    }
  }

  func unpin() {
    state.pinned = false
    if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    if !hovering { set(meeting.peek != nil ? .peek : .collapsed) } else { openedByHover = true }
  }
}

/// Target for the menu bar icon's clicks (AppKit needs an Objective-C object).
private final class StatusTarget: NSObject {
  let action: () -> Void
  init(_ action: @escaping () -> Void) { self.action = action }
  @objc func fire() { action() }
}

// MARK: - Shape: the island hangs from the top of the screen like the notch

/// The island's outline. `flare` curves the top corners outwards, the way the notch meets the menu bar: the outline is
/// `flare` points wider on each side at the very top. `corner` rounds the bottom corners.
struct NotchSilhouette: Shape {
  var corner: CGFloat
  var flare: CGFloat

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(corner, flare) }
    set { (corner, flare) = (newValue.first, newValue.second) }
  }

  func path(in r: CGRect) -> Path {
    let c = min(corner, r.height / 2, r.width / 2)
    let f = min(flare, r.height / 2)
    return Path { p in
      p.move(to: CGPoint(x: r.minX - f, y: r.minY))
      p.addLine(to: CGPoint(x: r.maxX + f, y: r.minY))
      if f > 0 { p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: f) }
      p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: c)
      p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: c)
      if f > 0 { p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX - f, y: r.minY), radius: f) }
      p.closeSubpath()
    }
  }
}

// MARK: - Views

private let accent = Color(red: 0.36, green: 0.55, blue: 1.0)
private let card = Color(white: 0.075)
private let hairline = Color.white.opacity(0.08)
private let ok = Color(red: 0.24, green: 0.78, blue: 0.47)

struct IslandView: View {
  @ObservedObject var meeting: Meeting
  @ObservedObject var state: IslandState
  @ObservedObject var updater: Updater
  var onTapIsland: () -> Void

  var body: some View {
    let size = state.size(for: state.mode, running: meeting.running)
    let shift = state.shift(for: state.mode, running: meeting.running)
    ZStack(alignment: .top) {
      Group {
        if state.inMenuBar {
          // under the menu bar: a card, like a menu
          RoundedRectangle(cornerRadius: state.mode == .peek ? 20 : 24, style: .continuous).fill(Color.black)
            .overlay(RoundedRectangle(cornerRadius: state.mode == .peek ? 20 : 24, style: .continuous).stroke(hairline, lineWidth: 1))
        } else {
          NotchSilhouette(corner: state.mode == .collapsed ? 10 : 24,
                          flare: state.mode == .collapsed ? (meeting.running || state.restingPip ? 7 : 0) : 12)
            .fill(Color.black)
        }
      }
        .frame(width: size.width, height: size.height)
        .offset(x: shift)
        .contentShape(Rectangle())
        .onTapGesture { onTapIsland() }
      Group {
        switch state.mode {
        case .collapsed: collapsed
        case .peek: peekView
        case .expanded: expanded
        }
      }
      .frame(width: size.width, height: size.height, alignment: .top)
      .clipped()
      .offset(x: shift)
    }
    .frame(width: state.panelSize.width, height: state.panelSize.height, alignment: .top)
    .background(CommandLine.arguments.contains("--backdrop")
      ? LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.20), Color(white: 0.02)], startPoint: .top, endPoint: .bottom) : nil)  // clean stage for recordings
    .contextMenu { menu }
    .environment(\.colorScheme, .dark)
  }

  // MARK: collapsed: activity on the left of the notch, recording time on the right

  @ViewBuilder private var collapsed: some View {
    if meeting.running {
      collapsedEars
    } else if state.restingPip {
      HStack(spacing: 0) {
        PipPrint(size: 28).frame(width: IslandState.restingEar)
        Color.clear.frame(width: state.geometry.notchWidth)
      }
      .frame(height: state.geometry.height)
    } else {
      Color.clear
    }
  }

  private var collapsedEars: some View {
    HStack(spacing: 0) {
      Group {
        Pip(mood: pipMood, size: 24)
      }
      .frame(maxWidth: .infinity)
      Color.clear.frame(width: state.geometry.notchWidth)
      Group {
        if meeting.running, let start = meeting.startedAt {
          HStack(spacing: 5) {
            Image(systemName: meeting.paused ? "pause.fill" : "circle.fill")
              .font(.system(size: meeting.paused ? 8 : 7)).foregroundStyle(meeting.paused ? Color.orange : Color.red)
            TimelineView(.periodic(from: start, by: 1)) { ctx in
              Text(clock(meeting.elapsed(at: ctx.date))).font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(meeting.paused ? Color.gray : Color.white)
            }
          }
        } else if !meeting.notes.isEmpty {
          Circle().fill(accent).frame(width: 7, height: 7)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .frame(height: state.geometry.height)
    .font(.system(size: 13))
  }

  // MARK: peek: the agent's new note

  private var peekView: some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear.frame(height: state.peekTop)
      HStack(spacing: 10) {
        Pip(mood: .whisper, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(meeting.peekFromPip ? "Pip" : state.agentName).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
          Text(meeting.peek ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.horizontal, 18)
  }

  // MARK: expanded: tabs around the notch, then a card

  private var expanded: some View {
    VStack(spacing: 8) {
      topBar
      HStack(spacing: 10) {
        sidebar
        editor
      }
      .padding(10)
      .background(RoundedRectangle(cornerRadius: 18).fill(card))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(hairline, lineWidth: 1))
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
    }
  }

  private var topBar: some View {
    HStack(spacing: 4) {
      tabButton(.live, "waveform")
      tabButton(.notes, "text.bubble")
      Spacer()
      Color.clear.frame(width: state.notchGap)
      Spacer()
      Button { meeting.toggleAgent() } label: {
        HStack(spacing: 5) {
          Image(systemName: meeting.agentEnabled ? "sparkles" : "moon.zzz").font(.system(size: 13, weight: .semibold))
          Text(meeting.agentEnabled ? state.agentName : "off").font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(meeting.agentEnabled ? accent : .gray)
        .padding(.horizontal, 9).frame(height: 26)
        .background(Capsule().fill(meeting.agentEnabled ? accent.opacity(0.16) : Color.white.opacity(0.06)))
      }
      .buttonStyle(.plain)
      .help(L10n.t(meeting.agentEnabled ? "agentOn" : "agentOff"))
      if let dir = meeting.dir {
        iconButton("folder") { NSWorkspace.shared.open(dir) }
      }
      starButton
      Menu { menu } label: {
        Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(.gray).frame(width: 34, height: 28)
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
    .padding(.horizontal, 14)
    .frame(height: state.band)
  }

  /// A small star that opens Pip's GitHub page (starring needs the user's own GitHub account, so the click on
  /// « Star » stays theirs). Filled and yellow once clicked, so it stops asking.
  @AppStorage("starClicked") private var starClicked = false

  private var starButton: some View {
    Button {
      starClicked = true
      NSWorkspace.shared.open(URL(string: "https://github.com/pjksens/heypip")!)
    } label: {
      Image(systemName: starClicked ? "star.fill" : "star").font(.system(size: 14, weight: .medium))
        .foregroundStyle(starClicked ? Color(red: 1, green: 0.84, blue: 0.04) : .gray)
        .frame(width: 30, height: 26)
    }
    .buttonStyle(.plain)
    .help(L10n.t("star"))
  }

  private func tabButton(_ tab: IslandTab, _ symbol: String) -> some View {
    Button { state.tab = tab } label: {
      Image(systemName: symbol).font(.system(size: 14, weight: .medium))
        .foregroundStyle(state.tab == tab ? .white : .gray)
        .frame(width: 40, height: 26)
        .background(Capsule().fill(state.tab == tab ? Color.white.opacity(0.13) : .clear))
    }
    .buttonStyle(.plain)
  }

  private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.gray).frame(width: 30, height: 26)
    }
    .buttonStyle(.plain)
  }

  // left column: listening orb, meeting name, live checks, start / stop
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 10) {
      Pip(mood: pipMood, size: 64).frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: 1) {
        meetingSwitcher
        Text(meeting.status).font(.system(size: 11.5)).foregroundStyle(.gray).lineLimit(2)
      }
      VStack(alignment: .leading, spacing: 7) {
        check(L10n.t("you"), on: meeting.hears[.me] == true, waiting: meeting.running)
        check(L10n.t("them"), on: meeting.hears[.them] == true, waiting: meeting.running)
        if meeting.agentEnabled, meeting.running, meeting.agentReading == false {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
              Text(state.agentName).font(.system(size: 13)).foregroundStyle(.gray)
              Text(L10n.t("noAgentShort")).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(2)
            }
          }
          .help(L10n.t("noAgent"))
        } else if meeting.agentEnabled {
          check(state.agentName, on: !meeting.notes.isEmpty || meeting.agentReading == true, waiting: meeting.running)
        } else {
          HStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(.system(size: 12)).foregroundStyle(.gray).frame(width: 16)
            Text(state.agentName + " · off").font(.system(size: 13)).foregroundStyle(.gray)
          }
        }
      }
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        if meeting.running {
          Button { meeting.togglePause() } label: {
            Image(systemName: meeting.paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .bold))
          }
          .buttonStyle(RoundButton())
          .help(L10n.t(meeting.paused ? "resume" : "pause"))
        }
        Button(meeting.running ? L10n.t("stop") : L10n.t("start")) { meeting.toggle() }
          .buttonStyle(PillButton(stop: meeting.running))
          .disabled(meeting.busy)
      }
    }
    .frame(width: 150, alignment: .leading)
    .padding(.leading, 6)
    .padding(.vertical, 4)
  }

  /// The meeting's name; between meetings, a menu to start a new one or look back at a recent one.
  @ViewBuilder private var meetingSwitcher: some View {
    let title = !meeting.name.isEmpty ? meeting.name
      : (!meeting.running ? meeting.dir.map(Store.meetingLabel) : nil) ?? L10n.t("meeting")
    let label = Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
    if meeting.running {
      label
    } else {
      Menu {
        Button(L10n.t("newMeeting")) { meeting.newMeetingView() }
        Divider()
        ForEach(Store.recentMeetings(), id: \.self) { dir in
          Button((dir == meeting.dir ? "✓ " : "") + Store.meetingLabel(dir)) { meeting.show(dir) }
        }
      } label: {
        HStack(spacing: 4) {
          label
          Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.gray)
        }
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
      .help(L10n.t("recent"))
    }
  }

  private func check(_ label: String, on: Bool, waiting: Bool) -> some View {
    HStack(spacing: 8) {
      ZStack {
        if on {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(ok)
        } else if waiting {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "circle").foregroundStyle(Color.white.opacity(0.25))
        }
      }
      .font(.system(size: 13))
      .frame(width: 16)
      Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? .white : .gray)
    }
  }

  // right panel: an editor-like view of transcript.md (or the notes)
  private var editor: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        HStack(spacing: 6) {
          Text("MD").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 3).padding(.vertical, 1.5).background(RoundedRectangle(cornerRadius: 3).fill(accent))
          Text(state.tab == .live ? "transcript.md" : "notes.md").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white)
          if meeting.running { Circle().fill(Color.orange).frame(width: 5, height: 5) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        Spacer()
        Text(meeting.dir.map { "~/…/" + $0.lastPathComponent } ?? "~/Documents/Pip")
          .font(.system(size: 11, design: .monospaced)).foregroundStyle(.gray).lineLimit(1).truncationMode(.middle)
      }
      .padding(8)
      Rectangle().fill(hairline).frame(height: 1)
      if !meeting.running && meeting.feed.isEmpty {
        startForm
      } else if state.tab == .live {
        transcript
      } else {
        notesList
      }
    }
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.045)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(hairline, lineWidth: 1))
  }

  private var startForm: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField(L10n.t("namePlaceholder"), text: $meeting.name)
        .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        .onSubmit { meeting.toggle() }
      Label(L10n.t("consent"), systemImage: "hand.raised").font(.system(size: 12)).foregroundStyle(.gray)
      Label(L10n.t(meeting.agentEnabled ? "agentOn" : "agentOff"), systemImage: meeting.agentEnabled ? "sparkles" : "moon.zzz")
        .font(.system(size: 12)).foregroundStyle(meeting.agentEnabled ? accent : .gray)
      Label(Locale(identifier: L10n.isFrench ? "fr" : "en").localizedString(forIdentifier: Store.languageID) ?? Store.languageID, systemImage: "globe")
        .font(.system(size: 12)).foregroundStyle(.gray)
      Spacer(minLength: 0)
    }
    .padding(12)
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(meeting.feed.suffix(80)) { item in row(item) }
          ForEach([Speaker.them, Speaker.me], id: \.self) { who in
            if let v = meeting.volatile[who] {
              row(FeedItem(time: Date(), kind: .speech(who), text: v), volatile: true)
            }
          }
          Color.clear.frame(height: 1).id("end")
        }
        .padding(.vertical, 6)
      }
      .onChange(of: meeting.feed.count) { proxy.scrollTo("end") }
      .onChange(of: meeting.volatile) { proxy.scrollTo("end") }
    }
  }

  private var notesList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if meeting.notes.isEmpty {
          Text(L10n.t("agentHint")).font(.system(size: 12)).foregroundStyle(.gray)
        }
        ForEach(Array(meeting.notes.enumerated()), id: \.offset) { i, n in
          Text(n).font(.system(size: i == 0 ? 14 : 12.5, weight: i == 0 ? .semibold : .regular))
            .foregroundStyle(i == 0 ? Color.white : Color.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(12)
    }
  }

  private func row(_ item: FeedItem, volatile: Bool = false) -> some View {
    let time = item.time.formatted(date: .omitted, time: .shortened)
    let isNote: Bool
    let who: String
    let color: Color
    switch item.kind {
    case .speech(let s): isNote = false; who = s.label; color = s == .me ? accent : .white
    case .note: isNote = true; who = "+ " + state.agentName; color = ok
    }
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(time).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.white.opacity(0.3)).frame(width: 38, alignment: .trailing)
      Text("\(Text(who).bold().foregroundColor(color))  \(Text(item.text).foregroundColor(.white.opacity(isNote ? 1 : 0.88)))")
        .font(.system(size: 12, design: .monospaced))
        .italic(volatile)
        .opacity(volatile ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2).padding(.horizontal, 8)
    .background(isNote ? ok.opacity(0.13) : .clear)
    .overlay(alignment: .leading) { if isNote { Rectangle().fill(ok).frame(width: 2) } }
  }

  @ViewBuilder private var menu: some View {
    Button(meeting.running ? L10n.t("stop") : L10n.t("start")) { meeting.toggle() }
    if meeting.running {
      Button(L10n.t(meeting.paused ? "resume" : "pause")) { meeting.togglePause() }
    }
    Toggle(L10n.t("agentToggle"), isOn: Binding(get: { meeting.agentEnabled }, set: { _ in meeting.toggleAgent() }))
    Toggle(L10n.t("inMenuBar"), isOn: $state.inMenuBar)
    if !state.inMenuBar {
      Toggle(L10n.t("restingPip"), isOn: $state.restingPip)
    }
    Menu(L10n.t("language")) {
      ForEach(state.languages, id: \.identifier) { loc in
        let name = Locale(identifier: L10n.isFrench ? "fr" : "en").localizedString(forIdentifier: loc.identifier) ?? loc.identifier
        let selected = Store.languageID.replacingOccurrences(of: "_", with: "-") == loc.identifier.replacingOccurrences(of: "_", with: "-")
        Button((selected ? "✓ " : "") + name) { Store.languageID = loc.identifier }
      }
    }
    Menu(L10n.t("interface")) {
      ForEach([("", L10n.t("auto")), ("en", "English"), ("fr", "Français")], id: \.0) { code, label in
        Button((L10n.override == code ? "✓ " : "") + label) { UserDefaults.standard.set(code, forKey: "uiLanguage") }
      }
    }
    Button(L10n.t("vocabulary")) { NSWorkspace.shared.open(Store.vocabularyFile) }
    Menu(L10n.t("recent")) {
      ForEach(Store.recentMeetings(), id: \.self) { dir in
        Button((dir == meeting.dir ? "✓ " : "") + Store.meetingLabel(dir)) { meeting.show(dir) }.disabled(meeting.running)
      }
    }
    Button(L10n.t("meetings")) {
      try? FileManager.default.createDirectory(at: Store.root, withIntermediateDirectories: true)
      NSWorkspace.shared.open(Store.root)
    }
    Divider()
    if let v = updater.available {
      Button(String(format: L10n.t("updateAvailable"), v)) { updater.installNow() }.disabled(meeting.running)
    } else {
      Button(L10n.t("checkUpdates")) { Task { await updater.check(install: false) } }
    }
    if let st = updater.status { Text(st) }
    Button(L10n.t("about")) { NSWorkspace.shared.open(URL(string: "https://github.com/pjksens/heypip")!) }
    Button(L10n.t("madeBy")) { NSWorkspace.shared.open(URL(string: "https://sachapraljak.com/?utm_source=pip&utm_medium=app&utm_campaign=heypip")!) }
    Divider()
    Button(L10n.t("quit")) { NSApp.terminate(nil) }
  }

  private var pipMood: PipMood { meeting.mood }

  private func clock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
  }
}

/// Bars that move while listening.
struct Bars: View {
  var color: Color
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
      let t = ctx.date.timeIntervalSinceReferenceDate
      HStack(spacing: 2.5) {
        ForEach(0..<4) { i in
          Capsule().fill(color).frame(width: 3, height: 5 + 10 * abs(sin(t * 4.6 + Double(i) * 1.1)))
        }
      }
      .frame(height: 16)
    }
  }
}

struct RoundButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .frame(width: 34, height: 34)
      .background(Circle().fill(Color.white.opacity(0.14)))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

struct PillButton: ButtonStyle {
  var stop: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(stop ? Color.white : Color.black)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(Capsule().fill(stop ? Color.red.opacity(0.88) : Color.white))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

extension Meeting {
  /// How Pip looks right now (the island and the menu bar icon).
  var mood: PipMood {
    if peek != nil && agentEnabled { return .whisper }
    if failed { return .error }
    if busy { return .preparing }
    if running {
      if paused { return .paused }
      return (hears[.me] == true || hears[.them] == true) ? .listening : .quiet
    }
    if let end = endedAt, Date().timeIntervalSince(end) < 300 { return .done }
    return .idle
  }
}
