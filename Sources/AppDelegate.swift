import AppKit
import AVFoundation
import Combine
import Network
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let settings = AppSettings.shared
    let history = HistoryStore.shared
    let recorder = Recorder()
    let hotkey = HotkeyMonitor()
    let overlay = Overlay()
    let nav = MainModel()

    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var levelTimer: Timer?
    private var escMonitor: Any?
    private let pathMonitor = NWPathMonitor()
    private var wasOffline = false
    private var mainWindow: NSWindow?

    // Current recording
    private struct Session { let id: UUID; let url: URL; let app: NSRunningApplication?; let pressedAt: Date; let command: Bool }
    private var session: Session?
    private var commandSelection: String?   // text that was selected when command mode started
    private var screenContext: [UUID: String] = [:]   // text already in the field, per dictation (memory only)
    private var locked = false            // tap-to-toggle (hands-free) mode
    private var ignoreNextRelease = false

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        history.markInterrupted()
        history.purge(olderThanDays: settings.retentionDays)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        history.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .utterDockPreferenceChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateDockPolicy(windowOpen: self.mainWindow?.isVisible ?? false)
            }
            .store(in: &cancellables)

        hotkey.onPress = { [weak self] in self?.keyDown() }
        hotkey.onRelease = { [weak self] in self?.keyUp() }
        hotkey.start()

        // Esc cancels a recording in progress
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelRecording() }
        }

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        Permissions.promptAccessibility()
        startNetworkWatch()

        openMain(settings.apiKey.isEmpty ? .settings : .home)
    }

    // Clicking the app in Finder/Spotlight while it's running opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMain(nav.tab)
        return true
    }

    // MARK: Hotkey state machine
    // Hold = push-to-talk. Quick tap = start hands-free; tap again to finish.

    private func keyDown() {
        if session != nil {
            if locked {
                locked = false
                ignoreNextRelease = true
                stopRecording()
            }
            return
        }
        // Holding Shift as well = command mode (edit the selected text by voice)
        startRecording(command: NSEvent.modifierFlags.contains(.shift))
    }

    private func keyUp() {
        if ignoreNextRelease { ignoreNextRelease = false; return }
        guard let s = session, !locked else { return }
        if Date().timeIntervalSince(s.pressedAt) < 0.3 {
            locked = true
            overlay.listening(handsFree: true, command: s.command)
            return
        }
        stopRecording()
    }

    // MARK: Recording

    private func startRecording(command: Bool) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            overlay.error("Allow microphone access for Utter in System Settings")
            return
        }
        if command {
            guard Permissions.accessibilityGranted else {
                overlay.error("Command mode needs Accessibility access")
                return
            }
            commandSelection = SelectionReader.accessibilitySelection()
            if commandSelection == nil {
                // Browsers / Electron apps: grab the selection via ⌘C instead.
                Task { commandSelection = await SelectionReader.copySelection() }
            }
        } else {
            commandSelection = nil
        }
        let id = UUID()
        let url = history.audioURL(fileName: "\(id.uuidString).m4a")
        do {
            try recorder.start(to: url)
        } catch {
            overlay.error("Mic error: \(error.localizedDescription)")
            return
        }
        if !command && settings.useScreenContext && Permissions.accessibilityGranted,
           let onScreen = SelectionReader.focusedFieldText() {
            screenContext[id] = onScreen
        }
        session = Session(id: id, url: url, app: NSWorkspace.shared.frontmostApplication, pressedAt: Date(), command: command)
        locked = false
        AIClient.warmUp(config: settings.config)   // connect to the API while you talk
        play("Tink")
        overlay.listening(handsFree: false, command: command)
        updateIcon()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.overlay.level(self.recorder.level())
            }
        }
    }

    private func stopRecording() {
        guard let s = session else { return }
        session = nil
        levelTimer?.invalidate(); levelTimer = nil
        let duration = recorder.stop()
        updateIcon()

        if duration < 0.4 {   // accidental press
            try? FileManager.default.removeItem(at: s.url)
            overlay.hide()
            return
        }
        if s.command && (commandSelection ?? "").isEmpty {
            try? FileManager.default.removeItem(at: s.url)
            play("Basso")
            overlay.error("Select some text first, then hold Shift + \(settings.hotkey.short)")
            return
        }
        play("Pop")

        // Audio is already on disk; log it BEFORE any network call so nothing is ever lost.
        var item = Dictation(
            id: s.id, date: Date(), audioFile: s.url.lastPathComponent, duration: duration,
            appName: s.app?.localizedName ?? "Unknown", bundleID: s.app?.bundleIdentifier ?? "",
            raw: nil, clean: nil, status: .processing, error: nil)
        if s.command {
            item.mode = .command
            item.sourceText = commandSelection
        }
        commandSelection = nil
        history.add(item)
        overlay.processing(s.command ? "Rewriting" : (settings.cleanupEnabled ? "Polishing" : "Transcribing"))
        process(item.id, paste: true)
    }

    private func cancelRecording() {
        guard let s = session else { return }
        session = nil
        locked = false
        commandSelection = nil
        screenContext[s.id] = nil
        levelTimer?.invalidate(); levelTimer = nil
        _ = recorder.stop()
        try? FileManager.default.removeItem(at: s.url)
        updateIcon()
        overlay.message("Cancelled", seconds: 0.9)
    }

    // MARK: Pipeline: transcribe → clean up → paste

    func process(_ id: UUID, paste: Bool) {
        guard let item = history.item(id) else { return }
        let config = settings.config
        let url = history.audioURL(for: item)
        history.update(id) { $0.status = .processing; $0.error = nil }
        let started = Date()
        let category = AppCategory.of(bundleID: item.bundleID)
        let context = CleanupContext(appName: item.appName, category: category,
                                     tone: settings.tone(for: category), snippets: settings.snippets,
                                     screenText: screenContext.removeValue(forKey: id))

        Task {
            do {
                let raw = try await AIClient.transcribe(fileURL: url, config: config)
                var clean = raw
                var cleanupError: String? = nil
                if item.isCommand {
                    // Command mode: the speech is an instruction applied to the selected text.
                    guard let source = item.sourceText, !source.isEmpty else { throw AIError("No text was selected") }
                    guard !raw.isEmpty else { throw AIError("Didn't catch the instruction") }
                    clean = try await AIClient.command(selection: source, instruction: raw, config: config)
                } else if config.cleanupEnabled && !raw.isEmpty {
                    do {
                        clean = try await AIClient.cleanup(raw, context: context, config: config)
                    } catch {
                        clean = raw   // better raw text than nothing
                        cleanupError = error.localizedDescription
                    }
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                history.update(id) {
                    $0.raw = raw
                    $0.clean = clean
                    $0.status = .done
                    $0.cleanupError = cleanupError
                    $0.processingMs = ms
                    $0.sttModel = config.sttModel
                    $0.llmModel = (item.isCommand || config.cleanupEnabled) ? config.llmModel : nil
                }

                if paste {
                    deliver(clean, intendedBundleID: item.bundleID, cleanupFailed: cleanupError != nil)
                } else {
                    overlay.success("Recovered a dictation — it's in History", seconds: 2.2)
                }
            } catch {
                history.update(id) { $0.status = .failed; $0.error = error.localizedDescription }
                play("Basso")
                overlay.error("Saved, but couldn't transcribe. Retry from History")
            }
        }
    }

    private func deliver(_ text: String, intendedBundleID: String, cleanupFailed: Bool) {
        guard !text.isEmpty else { overlay.message("Didn't catch that", seconds: 1.2); return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if !Permissions.accessibilityGranted {
            Paster.copy(text)
            overlay.error("Copied. Turn on Accessibility so Utter can paste")
        } else if front != intendedBundleID && !intendedBundleID.isEmpty {
            // You switched apps while it was processing — don't paste into the wrong place.
            Paster.copy(text)
            overlay.success("Copied — press ⌘V to paste", seconds: 2.2)
        } else {
            Paster.paste(text, keepOnClipboard: settings.keepOnClipboard)
            if cleanupFailed {
                overlay.error("Cleanup failed, pasted raw text. See History")
            } else {
                overlay.success("Pasted")
            }
        }
    }

    @objc func retryFailed() {
        for d in history.items where d.status == .failed { process(d.id, paste: false) }
    }

    // MARK: Network recovery

    private func startNetworkWatch() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "utter.network"))
    }

    private func networkChanged(online: Bool) {
        guard online else { wasOffline = true; return }
        guard wasOffline else { return }
        wasOffline = false
        // Back online: quietly re-run anything that failed in the last 24h.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-86_400)
            for d in self.history.items where d.status == .failed && d.date > cutoff {
                self.process(d.id, paste: false)
            }
        }
    }

    // MARK: Menu bar

    private func updateIcon() {
        let image: NSImage?
        if session != nil {
            image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Utter — recording")
        } else if history.failedCount > 0 {
            image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: "Utter — failed dictations")
        } else if let brand = NSImage(named: "MenuBarIcon") {
            brand.size = NSSize(width: 18, height: 18)
            image = brand
        } else {
            image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Utter")
        }
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hint = NSMenuItem(title: "Hold \(settings.hotkey.label) to dictate", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        if !Permissions.accessibilityGranted {
            menu.addItem(item("⚠︎ Grant Accessibility access…", #selector(openAccessibility)))
        }
        if settings.apiKey.isEmpty {
            menu.addItem(item("⚠︎ Add your API key…", #selector(openSettings)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Open Utter", #selector(openHome), key: "o"))
        menu.addItem(item("History", #selector(openHistory), key: "h"))
        let failed = history.failedCount
        if failed > 0 {
            menu.addItem(item("Retry \(failed) failed dictation\(failed == 1 ? "" : "s")", #selector(retryFailed)))
        }
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Utter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc func openHome() { openMain(.home) }
    @objc func openHistory() { openMain(.history) }
    @objc func openSettings() { openMain(.settings) }

    func openMain(_ tab: Tab) {
        nav.tab = tab
        if mainWindow == nil {
            let actions = AppActions(
                retry: { [weak self] id in self?.process(id, paste: false) },
                retryAll: { [weak self] in self?.retryFailed() })
            let view = MainView(nav: nav, settings: settings, store: history, actions: actions)
            let size = NSSize(width: 900, height: 640)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Utter"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.contentViewController = NSHostingController(rootView: view)
            w.setContentSize(size)
            w.minSize = NSSize(width: 760, height: 520)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            mainWindow = w
        }
        updateDockPolicy(windowOpen: true)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // Menu bar app that shows in the Dock while its window is open (or always, if chosen).
    private func updateDockPolicy(windowOpen: Bool) {
        let policy: NSApplication.ActivationPolicy = (settings.alwaysShowInDock || windowOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func windowWillClose(_ notification: Notification) {
        updateDockPolicy(windowOpen: false)
    }

    private func play(_ sound: String) {
        guard settings.soundsEnabled else { return }
        NSSound(named: NSSound.Name(sound))?.play()
    }
}
