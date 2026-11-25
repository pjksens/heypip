import AppKit
import AVFoundation
import Foundation

/// One line of the live view: a sentence, or a note from the agent.
struct FeedItem: Identifiable {
  enum Kind { case speech(Speaker), note }
  let id = UUID()
  let time: Date
  let kind: Kind
  let text: String
}

/// Last time each side was heard, and last time it sent any audio at all (written from the audio queue).
final class Levels: @unchecked Sendable {
  private let lock = NSLock()
  private var last: [Speaker: Date] = [:]
  private var received: [Speaker: Date] = [:]
  func heard(_ who: Speaker) { lock.lock(); last[who] = Date(); lock.unlock() }
  func recent(_ who: Speaker, within s: TimeInterval = 2.5) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return last[who].map { Date().timeIntervalSince($0) < s } ?? false
  }
  func got(_ who: Speaker) { lock.lock(); received[who] = Date(); lock.unlock() }
  /// No audio at all from this side (not even silence) for `s` seconds.
  func stalled(_ who: Speaker, for s: TimeInterval) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return received[who].map { Date().timeIntervalSince($0) > s } ?? true
  }
  func reset() { lock.lock(); received = [:]; loudness = [:]; lock.unlock() }

  private var loudness: [Speaker: [(time: Date, rms: Float)]] = [:]
  /// Loudness of each buffer, kept for 1.5 s, to tell the call's echo from your voice.
  func loud(_ who: Speaker, _ rms: Float) {
    let now = Date()
    lock.lock(); defer { lock.unlock() }
    loudness[who, default: []].append((now, rms))
    loudness[who]!.removeAll { now.timeIntervalSince($0.time) > 1.5 }
  }
  /// The microphone only hears the call through the speakers (see Echo.swift).
  func micIsEcho() -> Bool {
    lock.lock(); let me = loudness[.me] ?? [], them = loudness[.them] ?? []; lock.unlock()
    let now = Date()
    func bins(_ s: [(time: Date, rms: Float)]) -> [Float] {
      var b = [Float](repeating: 0, count: 60)  // 1.2 s in 20 ms bins, oldest first
      for (time, rms) in s {
        let i = 59 - Int(now.timeIntervalSince(time) / 0.02)
        if b.indices.contains(i) { b[i] = max(b[i], rms) }
      }
      return b
    }
    return envelopesMatch(mic: bins(me), call: bins(them))
  }
}

/// A flag the audio queue can read.
final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var v = false
  var value: Bool {
    get { lock.lock(); defer { lock.unlock() }; return v }
    set { lock.lock(); v = newValue; lock.unlock() }
  }
}

/// Loudness of a buffer (root mean square of every 8th sample).
func rms(_ buf: AVAudioPCMBuffer) -> Float {
  guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return 0 }
  var sum: Float = 0
  let n = Int(buf.frameLength)
  for i in stride(from: 0, to: n, by: 8) { sum += ch[i] * ch[i] }
  return (sum / Float(max(1, n / 8))).squareRoot()
}

/// Is there sound in this buffer (not just silence)?
func hasSound(_ buf: AVAudioPCMBuffer) -> Bool { rms(buf) > 0.01 }

@MainActor final class Meeting: ObservableObject {
  @Published var running = false
  @Published var busy = false
  @Published var status = L10n.t("ready")
  @Published var name = ""
  /// Final sentences and agent notes, in order.
  @Published var feed: [FeedItem] = []
  /// Sound heard from each side in the last seconds.
  @Published var hears: [Speaker: Bool] = [:]
  @Published var volatile: [Speaker: String] = [:]
  /// Agent notes, newest first.
  @Published var notes: [String] = []
  /// A new note arrived: the island shows it briefly.
  @Published var peek: String?
  /// The peek is Pip's own message (no agent reading), not an agent note.
  @Published var peekFromPip = false
  /// Agent switch on during a meeting: is an agent following agent-feed.md? nil when unknown.
  @Published var agentReading: Bool?
  private var agentWarned = false
  private var agentCheckedAt: Date?
  /// When the agent switch was last turned on (or the meeting started with it on): the warning waits 20 s from there.
  private var agentOnAt: Date?
  @Published var startedAt: Date?
  /// Recording paused: audio is dropped (not transcribed, not saved) until resume.
  @Published var paused = false
  /// Last start failed or the capture stopped by itself.
  @Published var failed = false
  /// When the last meeting ended (Pip is happy for a few minutes).
  @Published var endedAt: Date?
  private var pausedAt: Date?
  private var pausedTotal: TimeInterval = 0
  private let pauseFlag = Flag()
  @Published var dir: URL?
  /// The agent follows agent-feed.md and writes notes.md. Off: transcription only, nothing for the agent.
  @Published var agentEnabled = Store.agentEnabled

  /// The live capture, or a recorded call played back (`--replay`).
  var capture: AudioSource = Capture()
  private var transcribers: [Speaker: Transcribing] = [:]
  private var notesTimer: Timer?
  private let levels = Levels()
  private var splitters: [Speaker: SentenceSplitter] = [:]
  private let echo = EchoText()
  /// Silences the call's echo in what the « You » transcriber hears (see Echo.swift).
  private let gate = MicGate()
  /// « You » sentences waiting EchoText.wait seconds before they are written (or dropped as an echo).
  private var pendingMe: [(time: Date, text: String)] = []
  /// « Them » sentences held only while an older « You » sentence is still waiting, so lines are written in time order.
  private var pendingThem: [(time: Date, text: String)] = []
  /// Last time the microphone was only hearing the call.
  private var micEchoAt: Date?
  private var levelsTimer: Timer?
  private var notesDate: Date?
  private var peekTask: Task<Void, Never>?
  private var captureStartedAt: Date?
  private var restarts = 0
  private var restarting = false
  private let timeFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

  func toggle() {
    // « Stop » turns into « Start » under the pointer: a double click on « Stop » must not start a new meeting
    if !running, let endedAt, Date().timeIntervalSince(endedAt) < 2 { return }
    Task { running ? await stop() : await start() }
  }

  /// Recording time, pauses excluded.
  func elapsed(at now: Date) -> TimeInterval {
    guard let startedAt else { return 0 }
    return now.timeIntervalSince(startedAt) - pausedTotal - (pausedAt.map { now.timeIntervalSince($0) } ?? 0)
  }

  func togglePause() {
    guard running else { return }
    paused.toggle()
    pauseFlag.value = paused
    let now = Date()
    if paused { pausedAt = now } else if let p = pausedAt { pausedTotal += now.timeIntervalSince(p); pausedAt = nil }
    status = L10n.t(paused ? "paused" : "listening")
    if paused { volatile = [:] }
    if let dir {
      let mark = "\n— \(L10n.t(paused ? "pause" : "resume")) (\(timeFormat.string(from: now))) —\n"
      Store.append(mark, to: dir.appendingPathComponent("transcript.md"))
      if agentEnabled { Store.append(mark, to: dir.appendingPathComponent("agent-feed.md")) }
    }
  }

  func start() async {
    guard !running, !busy else { return }
    busy = true
    defer { busy = false }
    do {
      status = L10n.t("preparing")
      failed = false
      endedAt = nil
      paused = false
      pausedAt = nil
      pausedTotal = 0
      pauseFlag.value = false
      guard await microphoneAllowed() else {
        throw NSError(domain: "Pip", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.t("noMic")])
      }
      let dir = try Store.newMeeting(name: name)
      self.dir = dir
      feed = []
      hears = [:]
      splitters = [.me: SentenceSplitter(), .them: SentenceSplitter()]
      echo.reset()
      gate.reset()
      pendingMe = []
      pendingThem = []
      agentReading = nil
      agentWarned = false
      agentCheckedAt = nil
      agentOnAt = Date()
      micEchoAt = nil
      volatile = [:]
      notes = []
      notesDate = nil
      let me = makeTranscriber(speaker: .me, fileURL: dir.appendingPathComponent("you.m4a"))
      let them = makeTranscriber(speaker: .them, fileURL: dir.appendingPathComponent("them.m4a"))
      transcribers = [.me: me, .them: them]
      let handler: @Sendable (Speaker, String, Bool) -> Void = { [weak self] who, text, final in
        Task { @MainActor in self?.handle(who, text, final) }
      }
      status = L10n.t("model")
      let words = Store.vocabulary
      try await me.start(languageID: Store.languageID, words: words, onResult: handler)
      try await them.start(languageID: Store.languageID, words: words, onResult: handler)
      let levels = self.levels
      let gate = self.gate
      let pauseFlag = self.pauseFlag
      capture.onAudio = { buf, who in
        levels.got(who)
        if pauseFlag.value { return }
        let loudness = rms(buf)
        Trace.log("A \(who.rawValue) \(loudness)")
        levels.loud(who, loudness)
        if loudness > 0.01 { levels.heard(who) }
        if who == .them { them.feed(buf) }
        if !MicGate.enabled { if who == .me { me.feed(buf) }; return }
        for b in who == .me ? gate.mic(buf) : gate.call(buf) { me.feed(b.original, heard: b.heard) }
      }
      capture.onError = { [weak self] msg in
        Task { @MainActor in
          self?.status = "\(L10n.t("captureStopped")) : \(msg)"
          self?.failed = true
        }
      }
      levels.reset()
      try await capture.start()
      captureStartedAt = Date()
      restarts = 0
      running = true
      startedAt = Date()
      status = L10n.t("listening")
      watchNotes()
      levelsTimer?.invalidate()
      levelsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.flush()
          let micEcho = self.levels.micIsEcho()
          if micEcho { self.micEchoAt = Date() }
          let me = self.levels.recent(.me) && !micEcho
          let now: [Speaker: Bool] = [.me: me, .them: self.levels.recent(.them)]
          if now != self.hears { self.hears = now }
          self.watchCapture()
          self.checkAgent()
        }
      }
    } catch {
      status = "\(L10n.t("error")) : \(error.localizedDescription)"
      failed = true
      await capture.stop()
      for t in transcribers.values { await t.stop() }
      transcribers = [:]
    }
  }

  func stop() async {
    guard running, !busy else { return }
    busy = true
    defer { busy = false }
    status = L10n.t("stopping")
    await capture.stop()
    if let me = transcribers[.me] { for b in gate.flush() { me.feed(b.original, heard: b.heard) } }
    for t in transcribers.values { await t.stop() }
    transcribers = [:]
    try? await Task.sleep(for: .milliseconds(300))  // last results still on their way to handle()
    flush(force: true)
    if let dir {
      let f = DateFormatter()
      f.dateFormat = "HH:mm"
      Store.append("\n— \(L10n.t("end")) (\(f.string(from: Date()))) —\n", to: dir.appendingPathComponent("transcript.md"))
      Store.append("\n— \(L10n.t("end")) (\(f.string(from: Date()))) —\n", to: dir.appendingPathComponent("agent-feed.md"))
    }
    levelsTimer?.invalidate()
    hears = [:]
    running = false
    startedAt = nil
    paused = false
    pausedAt = nil
    pauseFlag.value = false
    endedAt = Date()
    volatile = [:]
    name = ""  // « Start » is a new meeting, never the one that just ended
    status = L10n.t("ended")
    // keep reading notes for a few minutes: the agent may still write the summary
    DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
      guard let self, !self.running else { return }
      self.notesTimer?.invalidate()
    }
  }

  /// ScreenCaptureKit sends audio all the time, silence included. A side that sends nothing at all has stalled
  /// (the microphone changed, AirPods switching to call mode…): restart the capture, three times at most per meeting.
  private func watchCapture() {
    guard running, !busy, !restarting, restarts < 3, let since = captureStartedAt, Date().timeIntervalSince(since) > 4,
          levels.stalled(.me, for: 3) || levels.stalled(.them, for: 3) else { return }
    restarting = true
    restarts += 1
    Task {
      defer { restarting = false }
      await capture.stop()
      levels.reset()
      guard running else { return }
      do {
        try await capture.start()
        captureStartedAt = Date()
        if !running { await capture.stop() }
      } catch {
        status = "\(L10n.t("captureStopped")) : \(error.localizedDescription)"
        failed = true
      }
    }
  }

  private func handle(_ who: Speaker, _ raw: String, _ final: Bool) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let splitter = splitters[who] ?? SentenceSplitter()
    splitters[who] = splitter
    if final {
      volatile[who] = nil
      for sentence in splitter.final(text) { route(who, sentence) }
    } else {
      let (new, tail) = splitter.volatile(text)
      for sentence in new { route(who, sentence) }
      if who == .them { echo.them(tail) }
      volatile[who] = tail.isEmpty ? nil : who == .me ? echo.filter(tail) : tail
    }
  }

  /// « Them » is written at once; « You » waits a moment, so an echo of « Them » can be recognised and dropped.
  /// A « Them » sentence that comes after a « You » sentence still waiting is held until that one is written.
  private func route(_ who: Speaker, _ sentence: String) {
    if who == .them {
      echo.them(sentence)
      pendingThem.append((Date(), sentence))
      flush()
    } else {
      Trace.log("R me \(sentence)")
      pendingMe.append((Date(), sentence))
    }
  }

  /// Writes waiting sentences of both sides in time order.
  private func flush(force: Bool = false) {
    let now = Date()
    while true {
      let me = pendingMe.first
      if let them = pendingThem.first, me.map({ them.time <= $0.time }) ?? true {
        pendingThem.removeFirst()
        write(.them, them.text, at: them.time)
      } else if let me, force || now.timeIntervalSince(me.time) >= EchoText.wait {
        pendingMe.removeFirst()
        if let mine = echo.filter(me.text, at: me.time, micEcho: micEchoAt.map { me.time.timeIntervalSince($0) < 5 } ?? false) {
          Trace.log("W me \(mine)")
          write(.me, mine, at: me.time)
        } else {
          Trace.log("X text \(me.text)")
        }
      } else {
        break
      }
    }
  }

  /// Clears the island for a new meeting (« Start » then creates it).
  func newMeetingView() {
    guard !running else { return }
    feed = []
    notes = []
    dir = nil
    name = ""
    volatile = [:]
    peek = nil
    endedAt = nil
    status = L10n.t("ready")
  }

  /// Shows a past meeting in the island (its transcript and notes). « Start » still begins a new one.
  func show(_ meetingDir: URL) {
    guard !running else { return }
    let day = String(meetingDir.lastPathComponent.prefix(10))  // yyyy-MM-dd
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let text = (try? String(contentsOf: meetingDir.appendingPathComponent("transcript.md"), encoding: .utf8)) ?? ""
    var items: [FeedItem] = []
    for line in text.split(separator: "\n") {
      // [12:03:15] Toi: …
      guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
            let colon = line[close...].firstIndex(of: ":") else { continue }
      let clock = line[line.index(after: line.startIndex)..<close]
      let labelStart = line.index(close, offsetBy: 2, limitedBy: colon) ?? colon
      let label = line[labelStart..<colon].trimmingCharacters(in: .whitespaces)
      let said = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      let who: Speaker = ["You", "Toi"].contains(label) ? .me : .them
      items.append(FeedItem(time: f.date(from: "\(day) \(clock)") ?? Date(), kind: .speech(who), text: said))
    }
    let noteText = (try? String(contentsOf: meetingDir.appendingPathComponent("notes.md"), encoding: .utf8)) ?? ""
    notes = noteText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }.map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }.reversed()
    feed = Array(items.suffix(400))
    dir = meetingDir
    notesDate = nil
    peek = nil
    volatile = [:]
    status = Store.meetingTitle(meetingDir)
  }

  func write(_ who: Speaker, _ text: String, at time: Date = Date()) {
    let item = FeedItem(time: time, kind: .speech(who), text: text)
    feed.append(item)
    if feed.count > 400 { feed.removeFirst(feed.count - 400) }
    if let dir {
      let line = "[\(timeFormat.string(from: item.time))] \(who.label): \(text)\n"
      Store.append(line, to: dir.appendingPathComponent("transcript.md"))
      if agentEnabled { Store.append(line, to: dir.appendingPathComponent("agent-feed.md")) }
    }
  }

  func toggleAgent() {
    agentEnabled.toggle()
    Store.agentEnabled = agentEnabled
    if let dir, running {
      Store.append("\n— \(L10n.t(agentEnabled ? "agentOn" : "agentOff")) (\(timeFormat.string(from: Date()))) —\n", to: dir.appendingPathComponent("agent-feed.md"))
    }
    if agentEnabled {
      // switched on again: say it again if no agent reads within 20 s
      agentOnAt = Date(); agentWarned = false; agentCheckedAt = nil
    } else {
      peek = nil; agentReading = nil
    }
  }

  /// Every few seconds: is an agent following the feed? A note in this meeting, or another process with
  /// agent-feed.md open (`tail -F`, as the /pip skill does). After 20 s without one, Pip says so, once per switch-on.
  private func checkAgent() {
    guard running, agentEnabled, let dir else { return }
    if !notes.isEmpty { agentReading = true; return }
    let now = Date()
    if let at = agentCheckedAt, now.timeIntervalSince(at) < 3 { return }
    agentCheckedAt = now
    let path = FeedReaders.realPath(dir.appendingPathComponent("agent-feed.md").path)
    Task.detached(priority: .utility) {
      let reading = FeedReaders.any(path)
      await MainActor.run { [weak self] in
        guard let self, self.running, self.agentEnabled else { return }
        self.agentReading = reading || !self.notes.isEmpty
        Trace.log("AG reading \(self.agentReading == true ? 1 : 0)")
        if self.agentReading == false, !self.agentWarned, !self.paused,
           let on = self.agentOnAt, Date().timeIntervalSince(on) > 20 {
          self.agentWarned = true
          self.showPeek(L10n.t("noAgent"), fromPip: true)
        }
      }
    }
  }

  private func watchNotes() {
    notesTimer?.invalidate()
    notesTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.loadNotes() }
    }
  }

  private func loadNotes() {
    guard let url = dir?.appendingPathComponent("notes.md"),
          let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let date = attrs[.modificationDate] as? Date, date != notesDate,
          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    notesDate = date
    let new = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }.map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }.reversed()
    let latest = new.first
    let changed = latest != notes.first
    let added = new.count - notes.count
    if added > 0 {
      for n in new.prefix(added).reversed() { feed.append(FeedItem(time: Date(), kind: .note, text: n)) }
    }
    notes = Array(new)
    if changed, agentEnabled, let latest { showPeek(latest) }
  }

  private func showPeek(_ text: String, fromPip: Bool = false) {
    peekTask?.cancel()
    peekFromPip = fromPip
    peek = text
    Trace.log("PEEK \(fromPip ? "pip" : "agent") \(text)")
    if !Replay.active { NSSound(named: "Tink")?.play() }
    peekTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled else { return }
      self?.peek = nil
    }
  }
}

/// Is another process reading a file (an agent's `tail -F agent-feed.md`)? Looks at open files of the user's processes.
enum FeedReaders {
  /// The path the system reports for open files (`resolvingSymlinksInPath` drops `/private`, this does not).
  nonisolated static func realPath(_ path: String) -> String {
    guard let p = realpath(path, nil) else { return path }
    defer { free(p) }
    return String(cString: p)
  }

  nonisolated static func any(_ path: String) -> Bool {
    let me = getpid()
    let n = proc_listallpids(nil, 0)
    guard n > 0 else { return false }
    var pids = [pid_t](repeating: 0, count: Int(n) + 32)
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    for pid in pids.prefix(Int(max(count, 0))) where pid > 0 && pid != me {
      let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
      guard size > 0 else { continue }
      var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
      let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
      for fd in fds.prefix(Int(max(got, 0)) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == PROX_FDTYPE_VNODE {
        var info = vnode_fdinfowithpath()
        let r = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
        guard r == MemoryLayout<vnode_fdinfowithpath>.size else { continue }
        let p = withUnsafeBytes(of: info.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if p == path { return true }
      }
    }
    return false
  }
}
