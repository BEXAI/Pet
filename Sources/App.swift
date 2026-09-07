import AppKit

@main
enum PetTerminalMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let defaults = UserDefaults.standard
    var petPanel: PetPanel!
    var pet: PetView!
    var terminal: TerminalController!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var target: CGPoint?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var nextMove = 0.0
    var dragging = false, hidden = false, sleeping = false, updating = false
    var roam = true, pinned = false
    var speed: CGFloat = 55, petWidth: CGFloat = 160
    var forceReducedMotion = false
    var desiredTerminalSize = CGSize(width: 560, height: 340)
    var reducedMotion: Bool { forceReducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        // A second open request reuses the existing companion.
        if let id = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            })
        {
            NSApp.terminate(nil)
            return
        }
        do {
            guard let resources = Bundle.main.resourceURL else {
                throw NSError(
                    domain: "VioletEmber", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "The pet artwork is missing from the app."])
            }
            PetDefinition.current = try PetDefinition.load(directory: resources)
            let url = resources.appendingPathComponent(PetDefinition.current.spritesheetPath)
            pet = PetView(atlas: try SpriteAtlas(url: url))
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        defaults.register(defaults: [
            "roam": true, "speed": 55.0, "petWidth": 160.0, "terminalWidth": 560.0, "terminalHeight": 340.0,
        ])
        roam = defaults.bool(forKey: "roam")
        pinned = defaults.bool(forKey: "pinned")
        forceReducedMotion = defaults.bool(forKey: "reduceMotion")
        speed = min(120, max(15, defaults.double(forKey: "speed")))
        petWidth = min(240, max(100, defaults.double(forKey: "petWidth")))
        desiredTerminalSize = CGSize(
            width: max(380, defaults.double(forKey: "terminalWidth")),
            height: max(230, defaults.double(forKey: "terminalHeight")))
        buildMenuBar()
        buildMainMenu()
        let screen = currentScreen().visibleFrame
        let frame = CGRect(
            x: defaults.object(forKey: "petX") == nil ? screen.midX : defaults.double(forKey: "petX"),
            y: defaults.object(forKey: "petY") == nil ? screen.midY - 180 : defaults.double(forKey: "petY"),
            width: petWidth, height: petWidth * 208 / 192)
        petPanel = PetPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        petPanel.title = PetDefinition.current.displayName
        petPanel.setAccessibilityRole(.window)
        petPanel.setAccessibilitySubrole(.standardWindow)
        petPanel.isOpaque = false
        petPanel.backgroundColor = .clear
        petPanel.hasShadow = false
        petPanel.level = .floating
        petPanel.hidesOnDeactivate = false
        petPanel.isReleasedWhenClosed = false
        petPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        petPanel.contentView = pet
        let saved = defaults.string(forKey: "workingDirectory").map { URL(fileURLWithPath: $0) }
        let fallback = FileManager.default.homeDirectoryForCurrentUser
        let directory = saved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? fallback
        terminal = TerminalController(directory: directory, size: desiredTerminalSize)
        terminal.onHide = { [weak self] in self?.hideTerminal() }
        terminal.onPin = { [weak self] in self?.togglePin() }
        terminal.onFolder = { [weak self] in self?.chooseFolder() }
        pet.onClick = { [weak self] in self?.toggleTerminal() }
        pet.onMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        pet.onDragState = { [weak self] active in
            guard let self else { return }
            self.dragging = active
            self.target = nil
            self.nextMove = ProcessInfo.processInfo.systemUptime + 3
            if !active { self.save() }
        }
        pet.onDrag = { [weak self] p in self?.positionPet(p, screen: self?.screen(at: NSEvent.mouseLocation)) }
        if pinned, defaults.object(forKey: "terminalX") != nil {
            terminal.panel.setFrameOrigin(
                CGPoint(x: defaults.double(forKey: "terminalX"), y: defaults.double(forKey: "terminalY")))
        } else {
            let layout = OverlayGeometry.layout(pet: frame, terminalSize: desiredTerminalSize, in: screen)
            if let term = layout.terminal { terminal.panel.setFrame(term, display: false) }
        }
        terminal.panel.orderFrontRegardless()
        positionPet(frame.origin, screen: currentScreen())
        terminal.panel.delegate = self
        petPanel.orderFrontRegardless()
        terminal.pinButton.title = pinned ? "Unpin" : "Pin"
        terminal.focus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer?.tolerance = 0.006
        RunLoop.main.add(timer!, forMode: .common)
    }

    func currentScreen() -> NSScreen { screen(at: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0] }
    func screen(at point: CGPoint) -> NSScreen? { NSScreen.screens.first { $0.frame.contains(point) } }

    func positionPet(_ origin: CGPoint, screen requested: NSScreen? = nil) {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        let screen = requested ?? petPanel.screen ?? currentScreen()
        let frame = CGRect(origin: origin, size: CGSize(width: petWidth, height: petWidth * 208 / 192))
        let attached = terminal.panel.isVisible && !pinned
        let result = OverlayGeometry.layout(
            pet: frame, terminalSize: attached ? desiredTerminalSize : nil, in: screen.visibleFrame)
        petPanel.setFrame(result.pet, display: true)
        if let frame = result.terminal {
            terminal.panel.setFrame(frame, display: true)
        } else if terminal.panel.isVisible {
            let display = terminal.panel.screen ?? screen
            terminal.panel.setFrame(OverlayGeometry.fit(terminal.panel.frame, in: display.visibleFrame), display: true)
        }
    }

    @objc func tick() {
        guard petPanel != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        guard !hidden, !sleeping else { return }
        let underPointer = pet.hasPixel(at: NSEvent.mouseLocation)
        petPanel.ignoresMouseEvents = !dragging && !underPointer
        let usingTerminal =
            terminal.panel.isVisible
            && (terminal.panel.isKeyWindow || terminal.panel.inLiveResize
                || terminal.panel.frame.contains(NSEvent.mouseLocation))
        let paused = !roam || reducedMotion || dragging || usingTerminal || underPointer || NSApp.modalWindow != nil
        if paused {
            target = nil
            nextMove = max(nextMove, now + 1.4)
        }
        if !paused, target == nil, now >= nextMove {
            let screen = (petPanel.screen ?? currentScreen()).visibleFrame
            let proposed = CGRect(
                x: CGFloat.random(in: screen.minX...screen.maxX), y: CGFloat.random(in: screen.minY...screen.maxY),
                width: petWidth, height: petWidth * 208 / 192)
            target =
                OverlayGeometry.layout(
                    pet: proposed, terminalSize: terminal.panel.isVisible && !pinned ? desiredTerminalSize : nil,
                    in: screen
                ).pet.origin
        }
        var row = 0
        if !paused, let destination = target {
            row = destination.x >= petPanel.frame.minX ? 1 : 2
            let point = OverlayGeometry.step(
                from: petPanel.frame.origin, toward: destination, speed: speed, elapsed: elapsed)
            positionPet(point)
            if hypot(point.x - destination.x, point.y - destination.y) < 1 {
                target = nil
                nextMove = now + Double.random(in: 1.5...4)
                save()
            }
        }
        pet.animate(row: row, time: now, reduced: reducedMotion)
        // Gaze stays active even when roaming pauses for typing, dragging, or Reduce Motion.
        pet.trackMouse(at: NSEvent.mouseLocation)
    }

    @objc func toggleTerminal() {
        if terminal.panel.isVisible {
            hideTerminal()
        } else {
            hidden = false
            petPanel.orderFrontRegardless()
            terminal.panel.orderFrontRegardless()
            positionPet(petPanel.frame.origin)
            terminal.focus()
            save()
        }
    }
    func hideTerminal() {
        terminal.panel.orderOut(nil)
        target = nil
        nextMove = ProcessInfo.processInfo.systemUptime + 2
        save()
    }
    @objc func showTerminal() {
        if !terminal.panel.isVisible { toggleTerminal() } else { terminal.focus() }
    }
    @objc func togglePin() {
        pinned.toggle()
        terminal.pinButton.title = pinned ? "Unpin" : "Pin"
        positionPet(petPanel.frame.origin)
        save()
    }
    @objc func toggleRoam() {
        roam.toggle()
        target = nil
        save()
    }
    @objc func toggleReducedMotion() {
        forceReducedMotion.toggle()
        target = nil
        save()
    }
    @objc func toggleVisibility() {
        hidden.toggle()
        if hidden {
            petPanel.orderOut(nil)
            terminal.panel.orderOut(nil)
        } else {
            recall()
            petPanel.orderFrontRegardless()
        }
    }
    @objc func recall() {
        hidden = false
        target = nil
        let display = currentScreen()
        let f = display.visibleFrame
        positionPet(CGPoint(x: f.midX - petWidth / 2, y: f.midY - 150), screen: display)
        petPanel.orderFrontRegardless()
        if pinned {
            terminal.panel.setFrame(
                OverlayGeometry.fit(
                    CGRect(
                        x: f.midX - desiredTerminalSize.width / 2, y: f.midY, width: desiredTerminalSize.width,
                        height: desiredTerminalSize.height), in: f), display: true)
        }
        save()
    }
    @objc func setSpeed(_ sender: NSMenuItem) {
        speed = CGFloat(sender.tag)
        target = nil
        save()
    }
    @objc func setPetSize(_ sender: NSMenuItem) {
        petWidth = CGFloat(sender.tag)
        target = nil
        positionPet(petPanel.frame.origin)
        save()
    }

    @objc func chooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Open terminal here"
        picker.directoryURL = terminal.workingDirectory
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let directory = picker.url else { return }
        if terminal.terminal.process.running {
            let alert = NSAlert()
            alert.messageText = "Start a new terminal session?"
            alert.informativeText =
                "The current shell and its running commands will close. The new shell will open in \(directory.lastPathComponent)."
            alert.addButton(withTitle: "Start new session")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        terminal.stop { [weak self] in
            guard let self else { return }
            self.terminal.workingDirectory = directory
            self.terminal.terminal.feed(text: "\u{1b}[2J\u{1b}[H")
            self.terminal.focus()
            self.save()
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !updating else { return }
        desiredTerminalSize = terminal.panel.frame.size
        positionPet(petPanel.frame.origin)
        save()
    }
    func windowDidMove(_ notification: Notification) {
        guard !updating, terminal != nil, (terminal.panel.contentView as? NeonChrome)?.resizeFrom == nil else { return }
        if !pinned {
            pinned = true
            terminal.pinButton.title = "Unpin"
        }
        save()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideTerminal()
        return false
    }
    @objc func displaysChanged() {
        target = nil
        guard petPanel != nil else { return }
        positionPet(petPanel.frame.origin)
        save()
    }
    @objc func willSleep() {
        sleeping = true
        target = nil
    }
    @objc func didWake() {
        sleeping = false
        lastTick = ProcessInfo.processInfo.systemUptime
        nextMove = lastTick + 3
        displaysChanged()
    }

    func save() {
        guard petPanel != nil, terminal != nil else { return }
        defaults.set(roam, forKey: "roam")
        defaults.set(pinned, forKey: "pinned")
        defaults.set(speed, forKey: "speed")
        defaults.set(petWidth, forKey: "petWidth")
        defaults.set(forceReducedMotion, forKey: "reduceMotion")
        defaults.set(petPanel.frame.minX, forKey: "petX")
        defaults.set(petPanel.frame.minY, forKey: "petY")
        defaults.set(terminal.panel.frame.minX, forKey: "terminalX")
        defaults.set(terminal.panel.frame.minY, forKey: "terminalY")
        defaults.set(desiredTerminalSize.width, forKey: "terminalWidth")
        defaults.set(desiredTerminalSize.height, forKey: "terminalHeight")
        defaults.set(terminal.workingDirectory.path, forKey: "workingDirectory")
    }

    func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "flame.fill", accessibilityDescription: PetDefinition.current.displayName)
        statusItem.button?.toolTip = "Pet Terminal"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = makeMenu()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }
        let label = NSMenuItem(title: "Pet Terminal", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        _ = item("Open Terminal", #selector(showTerminal), "t")
        _ = item("Choose Terminal Folder…", #selector(chooseFolder))
        menu.addItem(.separator())
        item("Roam", #selector(toggleRoam)).state = roam ? .on : .off
        item("Pin Terminal", #selector(togglePin)).state = pinned ? .on : .off
        item("Reduce Motion", #selector(toggleReducedMotion)).state = reducedMotion ? .on : .off
        for (name, values, selected, action) in [
            ("Speed", [25, 55, 95], Int(speed), #selector(setSpeed(_:))),
            ("Pet Size", [120, 160, 210], Int(petWidth), #selector(setPetSize(_:))),
        ] {
            let parent = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (i, value) in values.enumerated() {
                let name = name == "Speed" ? ["Gentle", "Normal", "Lively"][i] : ["Small", "Medium", "Large"][i]
                let choice = NSMenuItem(title: name, action: action, keyEquivalent: "")
                choice.target = self
                choice.tag = value
                choice.state = selected == value ? .on : .off
                sub.addItem(choice)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        _ = item("Bring Pet Here", #selector(recall))
        _ = item(hidden ? "Show Pet" : "Hide Pet", #selector(toggleVisibility))
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Pet Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = makeMenu()
        appItem.submenu?.delegate = self
        main.addItem(appItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")
        for (name, action, key) in [
            ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSStandardKeyBindingResponding.selectAll(_:)), "a"),
        ] {
            submenu.addItem(NSMenuItem(title: name, action: action, keyEquivalent: key))
        }
        edit.submenu = submenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminal != nil else { return .terminateNow }
        timer?.invalidate()
        save()
        terminal.stop { DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if petPanel != nil {
            recall()
            showTerminal()
        }
        return true
    }
}
