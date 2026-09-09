import AppKit
import Carbon
import UniformTypeIdentifiers
import WhiteboardCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PanelView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.backgroundColor = NSColor.boardPaper.withAlphaComponent(0.98).cgColor
        layer?.cornerRadius = 15; layer?.borderWidth = 1
        layer?.borderColor = NSColor.boardInk.withAlphaComponent(0.12).cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AppController: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    let io = DispatchQueue(label: "Whiteboard.storage", qos: .utility)
    let typesetting = DispatchQueue(label:"Whiteboard.typesetting",qos:.utility)
    var renderingTeX = false
    var texDrafts: [TeXKind:String] = [:]
    var library: Library!
    var window: OverlayWindow!
    let canvas = CanvasView(frame: .zero)
    var shelf = PanelView(frame: .zero)
    var toolbar = PanelView(frame: .zero)
    var shelfStack = NSStackView()
    var cards = NSStackView()
    var titleLabel = NSTextField(labelWithString: "Whiteboard")
    var saveLabel = NSTextField(labelWithString: "Opening…")
    var zoomLabel = NSTextField(labelWithString: "100%")
    var search = NSSearchField()
    var statusControl: NSSegmentedControl!
    var statusItem: NSStatusItem!
    var hotKey: HotKey?
    var desktopHotKey: HotKey?
    var usingDesktop = false
    var cropPanel: PanelView?
    var desktopHint: NSMenuItem?
    var watches: [DirectoryWatch] = []
    var items: [ShelfItem] = []
    var shelfOrder = ShelfOrder()
    var activeURL: URL?
    var revision = 0, savedRevision = 0
    var dirtySince: TimeInterval?
    var saveWork: DispatchWorkItem?
    var refreshWork: DispatchWorkItem?
    var isSaving = false
    var pendingImports = 0
    var exporting = false
    var saveBlocked = false
    var terminationPending = false
    var afterSave: (() -> Void)?
    var collapsed = false
    var shelfPage = 0
    var libraryGeneration = 0
    var toolButtons: [DrawingTool: NSButton] = [:]
    var penWidthControl: NSButton?
    var finishControl: NSButton?
    var backgroundControl: NSButton?
    var automaticShapesControl: NSButton?
    var onScreen: CGDirectDisplayID?
    var isBusy = false { didSet { canvas.acceptsInput = !isBusy } }
    var memoryPressure: DispatchSourceMemoryPressure?
    var demoRoot: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Whiteboard/Demo Ideas",isDirectory:true) }
    var isDemo: Bool { library?.root.standardizedFileURL == demoRoot.standardizedFileURL }
    var root: URL {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--library"), args.indices.contains(i+1) { return URL(fileURLWithPath: args[i+1], isDirectory: true) }
        if let path = UserDefaults.standard.string(forKey: "libraryRoot") { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Whiteboard/Ideas", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu(); makeWindow(); configureCanvas(); makeStatusMenu()
        hotKey = HotKey(action: { [weak self] in self?.toggleBoard() })
        canvas.colour = UserDefaults.standard.string(forKey:"penColour") ?? "ink"
        let width = UserDefaults.standard.double(forKey:"penWidth"); if (1...12).contains(width) { canvas.penWidth = width }
        canvas.automaticShapes = UserDefaults.standard.object(forKey:"automaticShapes") == nil || UserDefaults.standard.bool(forKey:"automaticShapes")
        automaticShapesControl?.state = canvas.automaticShapes ? .on : .off
        if hotKey?.registered != true { statusItem.button?.toolTip = "Whiteboard · shortcut unavailable; use this menu to open" }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning,.critical], queue: .main)
        memoryPressure?.setEventHandler { [weak self] in self?.canvas.images.clear() }; memoryPressure?.resume()
        openLibrary(ProcessInfo.processInfo.arguments.contains("--demo") ? demoRoot : root)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window != nil { showBoard() }
        return true
    }
    private func makeMainMenu() {
        let main = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem(), fileItem = NSMenuItem()
        let appMenu = NSMenu(title: "Whiteboard")
        appMenu.addItem(withTitle: "Quit Whiteboard", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; main.addItem(appItem)
        let fileMenu = NSMenu(title:"File")
        for (title, action, key) in [("New idea",#selector(newIdea),"n"),("Rename…",#selector(renameIdea),""),("Import image…",#selector(importImageFile),"i"),("Insert LaTeX…",#selector(insertLaTeX),""),("Insert TikZ…",#selector(insertTikZ),""),("Edit selected equation / diagram…",#selector(editSelectedTeX),""),("Save a copy…",#selector(saveCopy),""),("Save selection as idea",#selector(saveSelection),""),("Export PNG…",#selector(exportPNG),"e"),("Export PDF…",#selector(exportPDF),""),("Export workspace preview…",#selector(exportWorkspace),""),("Capture screenshot…",#selector(captureScreenshot),""),("Save checkpoint",#selector(saveCheckpoint),""),("Recovery history…",#selector(showRecoveryHistory),""),("Recover previous save as a copy",#selector(recoverPrevious),""),("Choose ideas folder…",#selector(chooseFolder),""),("Open demo workspace",#selector(trySamples),"")] {
            fileMenu.addItem(withTitle:title,action:action,keyEquivalent:key).target = self
        }
        fileMenu.addItem(withTitle:"Return to my ideas",action:#selector(returnToIdeas),keyEquivalent:"").target = self
        fileItem.submenu = fileMenu; main.addItem(fileItem)
        let edit = NSMenu(title: "Edit")
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.insertItem(withTitle:"Undo",action:#selector(undo),keyEquivalent:"z",at:0).target = self
        let redoItem = edit.insertItem(withTitle:"Redo",action:#selector(redo),keyEquivalent:"z",at:1); redoItem.keyEquivalentModifierMask = [.command,.shift]; redoItem.target = self
        edit.addItem(.separator())
        edit.addItem(withTitle:"Duplicate selection",action:#selector(duplicateSelection),keyEquivalent:"d").target = self
        edit.addItem(withTitle:"Fresh copy without annotations",action:#selector(duplicateReference),keyEquivalent:"").target = self
        edit.addItem(withTitle:"Fit all content",action:#selector(fitContent),keyEquivalent:"1").target = self
        edit.addItem(withTitle:"Crop selected image…",action:#selector(cropImage),keyEquivalent:"").target = self
        edit.addItem(withTitle:"Restore full image",action:#selector(restoreImage),keyEquivalent:"").target = self
        let shapes = NSMenuItem(title:"Drawing shapes",action:nil,keyEquivalent:"")
        shapes.submenu = shapeMenu(); edit.addItem(shapes)
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    private func makeWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = OverlayWindow(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Whiteboard"; window.isOpaque = false; window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        window.level = .floating; window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        canvas.frame = content.bounds; canvas.autoresizingMask = [.width,.height]; content.addSubview(canvas)
        window.contentView = content
        buildShelf(); buildToolbar(); buildCropPanel(); move(to: screen); showBoard()
    }
    private func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded; button.font = .systemFont(ofSize: 12, weight: .medium)
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); button.imagePosition = .imageLeading }
        button.setAccessibilityLabel(title)
        return button
    }
    private func buildShelf() {
        guard let content = window.contentView else { return }
        shelf.removeFromSuperview(); shelf = PanelView(frame: .zero); shelf.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(shelf)
        shelfStack = NSStackView(); shelfStack.orientation = .vertical; shelfStack.alignment = .leading; shelfStack.spacing = 10
        shelfStack.translatesAutoresizingMaskIntoConstraints = false; shelf.addSubview(shelfStack)
        let header = NSStackView(); header.orientation = .horizontal; header.spacing = 10
        let mark = NSTextField(labelWithString: "✳"); mark.font = .systemFont(ofSize: 23, weight: .medium); mark.textColor = .boardInk
        header.addArrangedSubview(mark)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold); titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        header.addArrangedSubview(titleLabel)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); header.addArrangedSubview(spacer)
        saveLabel.font = .systemFont(ofSize: 11); saveLabel.textColor = .secondaryLabelColor; header.addArrangedSubview(saveLabel)
        header.addArrangedSubview(button("New", #selector(newIdea), symbol: "plus"))
        header.addArrangedSubview(button(isDemo ? "My ideas" : "Demo",isDemo ? #selector(returnToIdeas) : #selector(trySamples),symbol:isDemo ? "arrow.uturn.backward" : "play.circle"))
        header.addArrangedSubview(button("Screens", #selector(showScreens), symbol: "display.2"))
        header.addArrangedSubview(button(collapsed ? "Open shelf" : "Fold", #selector(toggleShelf), symbol: collapsed ? "chevron.down" : "chevron.up"))
        shelfStack.addArrangedSubview(header)
        if !collapsed {
            let filters = NSStackView(); filters.spacing = 10
            statusControl = NSSegmentedControl(labels: ["● Unfinished", "✓ Finished", "Archive"], trackingMode: .selectOne, target: self, action: #selector(filterShelf))
            statusControl.selectedSegment = 0; statusControl.segmentStyle = .rounded; filters.addArrangedSubview(statusControl)
            search = NSSearchField(); search.placeholderString = "Find a file…"; search.delegate = self
            search.widthAnchor.constraint(equalToConstant: 175).isActive = true; filters.addArrangedSubview(search)
            shelfStack.addArrangedSubview(filters)
            let scroll = NSScrollView(); scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = false; scroll.drawsBackground = false
            scroll.heightAnchor.constraint(equalToConstant: 48).isActive = true
            cards = NSStackView(); cards.orientation = .horizontal; cards.spacing = 8; cards.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            scroll.documentView = cards; shelfStack.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: shelfStack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            shelf.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            shelf.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            shelf.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.82),
            shelfStack.leadingAnchor.constraint(equalTo: shelf.leadingAnchor, constant: 16),
            shelfStack.trailingAnchor.constraint(equalTo: shelf.trailingAnchor, constant: -16),
            shelfStack.topAnchor.constraint(equalTo: shelf.topAnchor, constant: 12),
            shelfStack.bottomAnchor.constraint(equalTo: shelf.bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: shelfStack.widthAnchor)
        ])
        rebuildCards()
    }
    private func buildToolbar() {
        guard let content = window.contentView else { return }
        toolbar.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(toolbar)
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(stack)
        let symbols: [DrawingTool:String] = [.pen:"pencil.tip",.highlighter:"highlighter",.eraser:"eraser",.select:"cursorarrow",.text:"textformat",.hand:"hand.draw",.shape:"arrow.up.right"]
        for (i,tool) in DrawingTool.allCases.enumerated() {
            let b = button("", #selector(selectTool(_:)))
            b.image = NSImage(systemSymbolName: symbols[tool]!, accessibilityDescription: tool.rawValue.capitalized)
            b.setButtonType(.pushOnPushOff); b.toolTip = tool.rawValue.capitalized; b.setAccessibilityLabel(tool.rawValue.capitalized); b.tag = i
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true; b.heightAnchor.constraint(equalToConstant: 31).isActive = true
            stack.addArrangedSubview(b); toolButtons[tool] = b
            if tool == .shape { b.menu = shapeMenu() }
        }
        let capture = button("",#selector(captureScreenshot),symbol:"camera.viewfinder")
        capture.setAccessibilityLabel("Capture screenshot"); capture.toolTip = "Capture screenshot"; stack.addArrangedSubview(capture)
        let colours = ["ink","blue","red","green"]
        for (i,name) in colours.enumerated() {
            let b = button("", #selector(selectColour(_:))); b.contentTintColor = .ink(name); b.tag = i
            let size = NSSize(width:16,height:16)
            b.image = NSImage(size:size,flipped:false) { rect in NSColor.ink(name).setFill(); NSBezierPath(ovalIn:rect.insetBy(dx:2,dy:2)).fill(); return true }
            b.toolTip = "\(name.capitalized) ink"; b.setAccessibilityLabel(b.toolTip!)
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true; stack.addArrangedSubview(b)
        }
        let widthButton = button("3 pt",#selector(cycleWidth)); widthButton.identifier = NSUserInterfaceItemIdentifier("pen-width"); widthButton.toolTip = "Cycle pen width"; stack.addArrangedSubview(widthButton)
        penWidthControl = widthButton
        stack.addArrangedSubview(button("↶", #selector(undo), symbol: nil))
        stack.addArrangedSubview(button("↷", #selector(redo), symbol: nil))
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), toolbar.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8)
        ])
        let bottom = PanelView(frame: .zero); bottom.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(bottom)
        let row = NSStackView(); row.spacing = 9; row.translatesAutoresizingMaskIntoConstraints = false; bottom.addSubview(row)
        row.addArrangedSubview(button("−",#selector(zoomOut))); zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        row.addArrangedSubview(zoomLabel); row.addArrangedSubview(button("+",#selector(zoomIn)))
        row.addArrangedSubview(button("Fit",#selector(fitContent)))
        let automatic = NSButton(checkboxWithTitle:"Auto shapes",target:self,action:#selector(toggleAutomaticShapes(_:)))
        automatic.state = .on; automatic.font = .systemFont(ofSize:11)
        automatic.toolTip = "Sketch a shape with the pen. It snaps when you lift. Undo restores your ink; hold Shift to keep a stroke freehand."
        automaticShapesControl = automatic; row.addArrangedSubview(automatic)
        row.addArrangedSubview(button("Fresh space",#selector(freshSpace),symbol: "arrow.down"))
        let background = button("Desktop",#selector(cycleBackground),symbol:"square.on.square")
        backgroundControl = background; row.addArrangedSubview(background)
        let finish = button("Finish",#selector(finishIdea),symbol:"checkmark")
        finishControl = finish; row.addArrangedSubview(finish)
        row.addArrangedSubview(button("Export",#selector(exportPNG),symbol: "square.and.arrow.up"))
        let hide = button("Hide",#selector(hideBoard),symbol:"eye.slash")
        hide.toolTip = "Hide the board, or hold ⌘⇧Space for temporary desktop access and release to return."
        row.addArrangedSubview(hide)
        NSLayoutConstraint.activate([
            bottom.centerXAnchor.constraint(equalTo: content.centerXAnchor),bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor,constant: -16),
            row.leadingAnchor.constraint(equalTo: bottom.leadingAnchor,constant: 12),row.trailingAnchor.constraint(equalTo: bottom.trailingAnchor,constant: -12),
            row.topAnchor.constraint(equalTo: bottom.topAnchor,constant: 9),row.bottomAnchor.constraint(equalTo: bottom.bottomAnchor,constant: -9)
        ])
        updateTool()
    }
    private func configureCanvas() {
        canvas.onCropChange = { [weak self] cropping in self?.cropPanel?.isHidden = !cropping }
        canvas.onRecognition = { [weak self] name in
            self?.automaticShapesControl?.title = "Auto shapes · "+name
            self?.automaticShapesControl?.setAccessibilityLabel("Auto shapes. Recognised "+name+". Undo restores the original ink.")
        }
        canvas.onEditTeX = { [weak self] id in self?.editTeX(id) }
        canvas.onToolChange = { [weak self] in self?.updateTool() }
        canvas.onCopy = { [weak self] in self?.copySelection() }
        canvas.onEdit = { [weak self] in self?.edited() }
        canvas.onViewChange = { [weak self] in self?.edited(delay: 0.8) }
        canvas.onImport = { [weak self] data,ext,point in self?.importImage(data, ext: ext, at: point) }
        canvas.onHide = { [weak self] in self?.hideBoard() }
        canvas.onNew = { [weak self] in self?.newIdea() }
        canvas.onRename = { [weak self] in self?.renameIdea() }
        canvas.onExport = { [weak self] in self?.exportPNG() }
    }
    private func buildCropPanel() {
        guard let content = window.contentView else { return }
        let panel = PanelView(frame:.zero); panel.translatesAutoresizingMaskIntoConstraints = false; panel.isHidden = true
        let row = NSStackView(); row.spacing = 10; row.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString:"Drag the area to keep. Your original stays saved."); hint.font = .systemFont(ofSize:12)
        row.addArrangedSubview(hint); row.addArrangedSubview(button("Cancel",#selector(cancelCrop)))
        row.addArrangedSubview(button("Apply crop",#selector(applyCrop),symbol:"crop"))
        panel.addSubview(row); content.addSubview(panel); cropPanel = panel
        NSLayoutConstraint.activate([panel.centerXAnchor.constraint(equalTo:content.centerXAnchor),panel.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-76),row.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:12),row.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-12),row.topAnchor.constraint(equalTo:panel.topAnchor,constant:10),row.bottomAnchor.constraint(equalTo:panel.bottomAnchor,constant:-10)])
    }
    @objc func cropImage() { canvas.beginCrop() }
    @objc func applyCrop() { canvas.applyCrop() }
    @objc func cancelCrop() { canvas.cancelCrop() }
    @objc func restoreImage() { canvas.restoreImages() }
    func openLibrary(_ root: URL) {
        isBusy = true; libraryGeneration += 1; let generation = libraryGeneration
        io.async {
            do {
                let library = try Library(root: root)
                var items = try library.list()
                if items.isEmpty {
                    if root.standardizedFileURL == self.demoRoot.standardizedFileURL { try DemoContent.populate(library) }
                    else { _ = try library.create() }
                    items = try library.list()
                }
                DispatchQueue.main.async {
                    guard generation == self.libraryGeneration else { return }
                    self.library = library; self.items = items
                    self.shelfOrder = UserDefaults.standard.data(forKey:"shelfOrder:"+library.root.path).flatMap {try? JSONDecoder().decode(ShelfOrder.self,from:$0)} ?? ShelfOrder()
                    self.watches = IdeaStatus.allCases.compactMap { DirectoryWatch(url: library.folder($0)) { [weak self] in self?.scheduleRefresh() } }
                    self.isBusy = false; self.shelfPage = 0; self.buildShelf()
                    if !self.isDemo { UserDefaults.standard.set(root.path,forKey:"libraryRoot") }
                    let lastPath = UserDefaults.standard.string(forKey:"lastBoard:"+library.root.path)
                    if let first = items.first(where: {$0.url.path == lastPath}) ?? items.first(where: {$0.status == .unfinished}) ?? items.first(where: {$0.status == .finished}) ?? items.first { self.loadIdea(first.url) }
                }
            } catch { DispatchQueue.main.async { self.isBusy = false; self.showError(error) } }
        }
    }
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshShelf() }; refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: work)
    }
    private func refreshShelf() {
        guard let library else { return }; let generation = libraryGeneration
        io.async {
            do {
                let items = try library.list()
                DispatchQueue.main.async { guard generation == self.libraryGeneration else { return }; self.items = items; self.rebuildCards() }
            } catch { DispatchQueue.main.async { self.saveLabel.stringValue = "Folder unavailable" } }
        }
    }
    private func rebuildCards() {
        guard !collapsed else { return }
        for view in cards.arrangedSubviews { cards.removeArrangedSubview(view); view.removeFromSuperview() }
        let status = IdeaStatus.allCases[max(0,min(2,statusControl?.selectedSegment ?? 0))]
        let query = search.stringValue
        let matching = shelfOrder.sorted(items.filter { $0.status == status && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) })
        shelfPage = min(shelfPage,max(0,(matching.count-1)/100))
        for item in matching.dropFirst(shelfPage*100).prefix(100) {
            let b = button((status == .finished ? "✓  " : status == .unfinished ? "●  " : "  ")+item.title, #selector(openCard(_:)))
            let pinned = shelfOrder.pinned.contains(ShelfOrder.key(item))
            if pinned {
                b.image = NSImage(systemSymbolName:"pin.fill",accessibilityDescription:"Pinned")
                b.image?.size = NSSize(width:12,height:12); b.imagePosition = .imageLeading
            }
            b.identifier = NSUserInterfaceItemIdentifier(item.url.path)
            b.contentTintColor = status == .finished ? .systemGreen : status == .unfinished ? .systemRed : .secondaryLabelColor
            b.isBordered = false; b.wantsLayer = true
            let tint: NSColor = status == .finished ? .systemGreen : status == .unfinished ? .systemRed : .secondaryLabelColor
            b.layer?.backgroundColor = tint.withAlphaComponent(0.09).cgColor
            b.layer?.cornerRadius = 7; b.layer?.borderWidth = item.url == activeURL ? 1 : 0
            b.layer?.borderColor = tint.withAlphaComponent(0.5).cgColor
            b.attributedTitle = NSAttributedString(string:"  "+b.title+"  ",attributes:[.foregroundColor:tint,.font:NSFont.systemFont(ofSize:12,weight:.medium)])
            b.attributedAlternateTitle = b.attributedTitle
            b.heightAnchor.constraint(equalToConstant:30).isActive = true
            b.toolTip = "\(item.title) — \(status.rawValue)\nClick to reopen. Control-click for file actions."
            b.setAccessibilityLabel("\(item.title), \(status.rawValue)"+(shelfOrder.pinned.contains(ShelfOrder.key(item)) ? ", pinned" : ""))
            b.state = item.url == activeURL ? .on : .off
            b.menu = cardMenu(item)
            b.widthAnchor.constraint(equalToConstant:min(250,max(100,b.attributedTitle.size().width+(pinned ? 26 : 8)))).isActive = true
            cards.addArrangedSubview(b)
        }
        if matching.count > 100 {
            if shelfPage > 0 { cards.addArrangedSubview(button("Previous 100",#selector(previousShelfPage))) }
            let label = NSTextField(labelWithString:"\(shelfPage*100+1)–\(min(matching.count,(shelfPage+1)*100)) of \(matching.count)")
            label.font = .systemFont(ofSize:11); cards.addArrangedSubview(label)
            if (shelfPage+1)*100 < matching.count { cards.addArrangedSubview(button("Next 100",#selector(nextShelfPage))) }
        }
        if matching.isEmpty {
            let label = NSTextField(labelWithString: query.isEmpty ? "Your \(status.rawValue.lowercased()) ideas will live here." : "No matching files")
            label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 12); cards.addArrangedSubview(label)
        }
        cards.layoutSubtreeIfNeeded(); cards.setFrameSize(NSSize(width: max(300,cards.fittingSize.width),height: 36))
    }
    private func cardMenu(_ item: ShelfItem) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let pin = NSMenuItem(title:shelfOrder.pinned.contains(ShelfOrder.key(item)) ? "Unpin idea" : "Pin idea",action:#selector(pinCard(_:)),keyEquivalent:"")
        pin.target = self; pin.representedObject = item.url; menu.addItem(pin)
        for (title,offset) in [("Move earlier",-1),("Move later",1)] {
            let action = NSMenuItem(title:title,action:#selector(reorderCard(_:)),keyEquivalent:"")
            action.target = self; action.representedObject = item.url; action.tag = offset
            var preview = shelfOrder; action.isEnabled = preview.move(item,by:offset,among:items)
            menu.addItem(action)
        }
        menu.addItem(.separator())
        for status in IdeaStatus.allCases where status != item.status {
            let action = NSMenuItem(title: "Move to \(status.rawValue)", action: #selector(moveCard(_:)), keyEquivalent: "")
            action.target = self; action.representedObject = [item.url.path,status.rawValue]; menu.addItem(action)
        }
        let history = NSMenuItem(title:"Recovery history…",action:#selector(recoverCard(_:)),keyEquivalent:"")
        history.target = self; history.representedObject = item.url; menu.addItem(history)
        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(revealCard(_:)), keyEquivalent: "")
        reveal.target = self; reveal.representedObject = item.url; menu.addItem(reveal)
        return menu
    }
    private func saveShelfOrder() {
        if let data = try? JSONEncoder().encode(shelfOrder) { UserDefaults.standard.set(data,forKey:"shelfOrder:"+library.root.path) }
        rebuildCards()
    }
    @objc private func pinCard(_ sender: NSMenuItem) {
        guard !isBusy, let url = sender.representedObject as? URL, let item = items.first(where: {$0.url == url}) else { return }
        shelfOrder.togglePin(item); shelfPage = 0; saveShelfOrder()
    }
    @objc private func reorderCard(_ sender: NSMenuItem) {
        guard !isBusy, let url = sender.representedObject as? URL, let item = items.first(where: {$0.url == url}) else { return }
        if shelfOrder.move(item,by:sender.tag,among:items) { saveShelfOrder() }
    }
    @objc private func openCard(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        afterSaving { self.loadIdea(URL(fileURLWithPath: path, isDirectory: true)) }
    }
    func loadIdea(_ url: URL) {
        guard !isBusy else { return }; isBusy = true; saveLabel.stringValue = "Opening…"
        io.async {
            do {
                let board = try self.library.load(url)
                DispatchQueue.main.async {
                    self.activeURL = url; self.revision = 0; self.savedRevision = 0; self.dirtySince = nil; self.saveBlocked = false
                    self.canvas.load(board, at: url); UserDefaults.standard.set(url.path,forKey:"lastBoard:"+self.library.root.path); self.isBusy = false
                    self.statusControl?.selectedSegment = IdeaStatus.allCases.firstIndex(where: {$0.rawValue == url.deletingLastPathComponent().lastPathComponent}) ?? 0
                    self.automaticShapesControl?.title = "Auto shapes"; self.automaticShapesControl?.setAccessibilityLabel("Auto shapes")
                    self.updateLabels(); self.rebuildCards()
                }
            } catch { DispatchQueue.main.async { self.isBusy = false; self.showError(error) } }
        }
    }
    func edited(delay: Double = 0.4) {
        guard activeURL != nil else { return }
        revision += 1; saveLabel.stringValue = saveBlocked ? "Save a copy" : "Saving…"
        let now = ProcessInfo.processInfo.systemUptime
        if dirtySince == nil { dirtySince = now }
        zoomLabel.stringValue = "\(Int(canvas.board.viewport.zoom*100))%"
        saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.saveNow() }; saveWork = work
        let boundedDelay = min(delay,max(0,2-(now-(dirtySince ?? now))))
        DispatchQueue.main.asyncAfter(deadline: .now()+boundedDelay, execute: work)
    }
    func saveNow() {
        saveWork?.cancel(); saveWork = nil
        guard !isSaving, !saveBlocked, let url = activeURL else { return }
        guard revision != savedRevision else { guard pendingImports == 0 else { return }; let action = afterSave; afterSave = nil; action?(); return }
        isSaving = true; let board = canvas.board, savingRevision = revision
        io.async {
            let result = Result { try self.library.save(board, at: url) }
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success:
                    self.savedRevision = savingRevision; self.dirtySince = self.revision == savingRevision ? nil : ProcessInfo.processInfo.systemUptime; self.updateLabels()
                    if self.revision != self.savedRevision { self.saveNow() }
                    else if self.pendingImports == 0 { let action = self.afterSave; self.afterSave = nil; action?() }
                case .failure(let error):
                    self.saveBlocked = true; self.afterSave = nil; self.isBusy = false; self.saveLabel.stringValue = "Save a copy"
                    if self.terminationPending { self.terminationPending = false; NSApp.reply(toApplicationShouldTerminate:false) }
                    self.showError(error)
                }
            }
        }
    }
    private func afterSaving(_ action: @escaping () -> Void) {
        guard !isBusy, afterSave == nil else { return }
        canvas.finishEditing(); canvas.finishGesture()
        guard !saveBlocked else { showError(BoardError.conflict); return }
        if activeURL == nil { action(); return }
        isBusy = true
        afterSave = { self.isBusy = false; action() }; saveNow()
    }
    private func updateLabels() {
        titleLabel.stringValue = activeURL?.deletingPathExtension().lastPathComponent ?? "Whiteboard"
        saveLabel.stringValue = saveBlocked ? "Save a copy" : savedRevision == revision ? "Saved locally" : "Saving…"
        zoomLabel.stringValue = "\(Int(canvas.board.viewport.zoom*100))%"
        if isDemo { saveLabel.stringValue = "Demo · "+saveLabel.stringValue }
        penWidthControl?.title = "\(canvas.penWidth.formatted()) pt"
        let finished = activeURL?.deletingLastPathComponent().lastPathComponent == IdeaStatus.finished.rawValue
        finishControl?.title = finished ? "Reopen" : "Finish"
        finishControl?.setAccessibilityLabel(finished ? "Reopen idea" : "Finish idea")
        finishControl?.image = NSImage(systemSymbolName:finished ? "arrow.uturn.backward" : "checkmark",accessibilityDescription:nil)
        backgroundControl?.title = ["paper":"Paper","dim":"Dim","transparent":"Desktop"][canvas.board.background] ?? "Desktop"
        backgroundControl?.setAccessibilityLabel("Background: "+(backgroundControl?.title ?? "Desktop"))
        backgroundControl?.toolTip = "Change background: desktop, paper or dim"
    }
    private func importImage(_ data: Data, ext: String, at point: Point) {
        guard let url = activeURL, !isBusy, data.count <= 32*1024*1024 else { return }
        let id = canvas.board.id; pendingImports += 1
        io.async {
            do {
                guard let dimensions = ImagePool.dimensions(data) else { throw BoardError.invalidData }
                let asset = try self.library.importAsset(data: data, extension: ext, to: url)
                let width = min(720, dimensions.width), height = width*dimensions.height/dimensions.width
                DispatchQueue.main.async {
                    self.pendingImports -= 1
                    guard self.activeURL == url, self.canvas.board.id == id else { return }
                    self.canvas.checkpoint(); self.canvas.board.images.append(BoardImage(asset: asset, frame: Rect(point.x,point.y,width,height)))
                    self.canvas.needsDisplay = true; self.edited(); if self.afterSave != nil { self.saveNow() }
                }
            } catch { DispatchQueue.main.async { self.pendingImports -= 1; self.showError(error); if self.afterSave != nil { self.saveNow() } } }
        }
    }
    private func makeStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Whiteboard")
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, key: String = "") {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        add("Show / hide board  ⇧⌘B", #selector(toggleBoard)); add("Bring board here", #selector(bringHere)); add("Move to display…",#selector(showScreens))
        let hint = NSMenuItem(title:desktopHotKey?.registered == true ? "Hold ⌘⇧Space to use the desktop" : "Desktop hold shortcut unavailable",action:nil,keyEquivalent:""); hint.isEnabled = false; desktopHint = hint; menu.addItem(hint)
        menu.addItem(.separator()); add("New idea",#selector(newIdea)); add("Rename current file…",#selector(renameIdea)); add("Save a copy…",#selector(saveCopy))
        add("Mark finished / unfinished",#selector(finishIdea)); add("Archive current idea",#selector(archiveIdea))
        menu.addItem(.separator()); add("Choose ideas folder…",#selector(chooseFolder)); add("Show ideas folder",#selector(revealFolder))
        add("Clear ink (undoable)",#selector(clearInk)); add("Lock / unlock selected image",#selector(lockImage))
        add("Save selection as idea",#selector(saveSelection)); add("Export PNG…",#selector(exportPNG)); add("Export PDF…",#selector(exportPDF)); add("Capture screenshot…",#selector(captureScreenshot)); add("Save checkpoint",#selector(saveCheckpoint)); add("Recovery history…",#selector(showRecoveryHistory)); add("Recover previous save as a copy",#selector(recoverPrevious))
        menu.addItem(.separator()); add("Controls & build notes",#selector(showHelp)); add("Quit Whiteboard",#selector(quit),key: "q")
        statusItem.menu = menu
    }
    @objc func toggleBoard() { window.isVisible ? hideBoard() : showBoard() }
    func showBoard() {
        usingDesktop = false; window.ignoresMouseEvents = false; window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true); window.makeFirstResponder(canvas)
        if desktopHotKey == nil {
            desktopHotKey = HotKey(keyCode:UInt32(kVK_Space),modifiers:UInt32(cmdKey|shiftKey),id:2,action:{ [weak self] in self?.beginDesktopAccess() },released:{ [weak self] in self?.endDesktopAccess() })
        }
        desktopHint?.title = desktopHotKey?.registered == true ? "Hold ⌘⇧Space to use the desktop" : "Desktop hold shortcut unavailable"
    }
    private func beginDesktopAccess() {
        guard !usingDesktop, window.isVisible, !isBusy, NSApp.modalWindow == nil else { return }
        canvas.finishEditing(); canvas.finishGesture(); saveNow()
        usingDesktop = true; window.ignoresMouseEvents = true; window.orderOut(nil)
    }
    private func endDesktopAccess() { guard usingDesktop else { return }; showBoard() }
    @objc func hideBoard() {
        usingDesktop = false; desktopHotKey = nil
        canvas.finishEditing(); canvas.finishGesture(); saveNow(); window.orderOut(nil); canvas.images.clear()
    }
    @objc func toggleShelf() {
        let status = statusControl?.selectedSegment ?? 0, query = search.stringValue
        collapsed.toggle(); buildShelf()
        statusControl?.selectedSegment = status; search.stringValue = query; rebuildCards()
    }
    @objc func filterShelf() { shelfPage = 0; rebuildCards() }
    @objc func nextShelfPage() { shelfPage += 1; rebuildCards() }
    @objc func previousShelfPage() { shelfPage = max(0,shelfPage-1); rebuildCards() }
    func controlTextDidChange(_ obj: Notification) { shelfPage = 0; rebuildCards() }
    @objc func selectTool(_ sender: NSButton) {
        if DrawingTool.allCases[sender.tag] == .shape {
            shapeMenu().popUp(positioning:nil,at:NSPoint(x:sender.bounds.maxX+4,y:sender.bounds.midY),in:sender)
        } else { canvas.tool = DrawingTool.allCases[sender.tag] }
        updateTool()
    }
    private func shapeMenu() -> NSMenu {
        let menu = NSMenu()
        for (i,shape) in DrawingShape.allCases.enumerated() {
            let title = ["Line  ·  L","Arrow  ·  A","Rectangle  ·  R","Ellipse  ·  O"][i]
            let item = NSMenuItem(title:title,action:#selector(selectShape(_:)),keyEquivalent:"")
            item.target = self; item.tag = i; item.state = canvas.tool == .shape && canvas.shape == shape ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator()); let hint = NSMenuItem(title:"Hold Shift for equal sides or 45° angles",action:nil,keyEquivalent:""); hint.isEnabled = false; menu.addItem(hint)
        return menu
    }
    @objc private func selectShape(_ sender: NSMenuItem) { canvas.finishGesture(); canvas.shape = DrawingShape.allCases[sender.tag]; canvas.tool = .shape }
    @objc private func toggleAutomaticShapes(_ sender: NSButton) {
        canvas.finishGesture(); canvas.automaticShapes = sender.state == .on
        sender.title = "Auto shapes"; sender.setAccessibilityLabel("Auto shapes")
        UserDefaults.standard.set(canvas.automaticShapes,forKey:"automaticShapes")
    }
    private func updateTool() {
        for (tool,button) in toolButtons { button.state = canvas.tool == tool ? .on : .off }
        let symbols: [DrawingShape:String] = [.line:"line.diagonal",.arrow:"arrow.up.right",.rectangle:"rectangle",.ellipse:"oval"]
        toolButtons[.shape]?.image = NSImage(systemSymbolName:symbols[canvas.shape]!,accessibilityDescription:"Shapes: "+canvas.shape.rawValue)
        toolButtons[.shape]?.setAccessibilityLabel("Shapes: "+canvas.shape.rawValue)
        toolButtons[.shape]?.toolTip = "Shapes · L line, A arrow, R rectangle, O ellipse. Shift constrains."
    }
    @objc func selectColour(_ sender: NSButton) { canvas.colour = ["ink","blue","red","green"][sender.tag]; UserDefaults.standard.set(canvas.colour,forKey:"penColour") }
    @objc func cycleWidth(_ sender: NSButton) {
        let widths = [1.5,3.0,6.0,10.0]; canvas.penWidth = widths.first(where: {$0 > canvas.penWidth}) ?? widths[0]
        sender.title = "\(canvas.penWidth.formatted()) pt"; UserDefaults.standard.set(canvas.penWidth,forKey:"penWidth")
    }
    @objc func fitContent() { canvas.fitContent() }
    @objc func duplicateSelection() { canvas.duplicateSelection() }
    @objc func duplicateReference() { canvas.duplicateSelection(withAnnotations:false) }
    @objc func undo() { canvas.undoEdit() }
    @objc func redo() { canvas.redoEdit() }
    @objc func clearInk() { canvas.clearInk() }
    @objc func zoomIn() { canvas.zoom(1.2) }
    @objc func zoomOut() { canvas.zoom(1/1.2) }
    @objc func freshSpace() { canvas.freshSpace() }
    @objc func cycleBackground() {
        let options = ["transparent","paper","dim"], current = options.firstIndex(of: canvas.board.background) ?? 0
        canvas.setBackground(options[(current+1)%options.count])
        updateLabels()
    }
    @objc func lockImage() {
        canvas.checkpoint()
        for i in canvas.board.images.indices where canvas.selected.contains(canvas.board.images[i].id) { canvas.board.images[i].locked.toggle() }
        canvas.needsDisplay = true; edited()
    }
    @objc func newIdea() {
        afterSaving {
            self.isBusy = true
            self.io.async {
                do { let url = try self.library.create(); DispatchQueue.main.async { self.isBusy = false; self.loadIdea(url); self.refreshShelf() } }
                catch { DispatchQueue.main.async { self.isBusy = false; self.showError(error) } }
            }
        }
    }
    private func askName(_ title: String, initial: String) -> String? {
        showBoard(); let alert = NSAlert(); alert.messageText = title
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0,y: 0,width: 320,height: 26)); field.stringValue = initial; alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    @objc func renameIdea() {
        guard let url = activeURL, let name = askName("Rename this idea", initial: url.deletingPathExtension().lastPathComponent) else { return }
        let status = IdeaStatus(rawValue: url.deletingLastPathComponent().lastPathComponent) ?? .unfinished
        afterSaving { self.moveFile(url, status: status, name: name) }
    }
    @objc func finishIdea() {
        guard let url = activeURL else { return }
        afterSaving { self.moveFile(url, status: url.deletingLastPathComponent().lastPathComponent == IdeaStatus.finished.rawValue ? .unfinished : .finished) }
    }
    @objc func archiveIdea() { guard let url = activeURL else { return }; afterSaving {self.moveFile(url,status:.archived)} }
    @objc func moveCard(_ sender: NSMenuItem) {
        guard let args = sender.representedObject as? [String], let status = IdeaStatus(rawValue: args[1]) else { return }
        afterSaving { self.moveFile(URL(fileURLWithPath:args[0],isDirectory:true),status:status) }
    }
    private func moveFile(_ url: URL, status: IdeaStatus, name: String? = nil) {
        isBusy = true
        io.async {
            do {
                let destination = try self.library.move(url,to:status,name:name)
                DispatchQueue.main.async {
                    if let old = self.items.first(where: {$0.url == url}) {
                        var new = old; new.url = destination; new.status = status
                        self.shelfOrder.relocate(from:old,to:new); self.saveShelfOrder()
                    }
                    if self.activeURL == url { self.activeURL = destination; self.statusControl?.selectedSegment = IdeaStatus.allCases.firstIndex(of:status) ?? 0; self.canvas.packageURL = destination; self.canvas.images.clear(); UserDefaults.standard.set(destination.path,forKey:"lastBoard:"+self.library.root.path); self.updateLabels() }
                    self.isBusy = false; self.refreshShelf()
                }
            } catch { DispatchQueue.main.async { self.isBusy = false; self.showError(error) } }
        }
    }
    @objc func saveCopy() {
        canvas.finishEditing(); canvas.finishGesture()
        guard let source = activeURL, let name = askName("Save an editable copy", initial: (activeURL?.deletingPathExtension().lastPathComponent ?? "Idea")+" copy") else { return }
        let board = canvas.board
        if saveBlocked { copyBoard(board, from: source, name: name) }
        else { afterSaving { self.copyBoard(self.canvas.board, from: source, name: name) } }
    }
    @objc func saveSelection() {
        guard let source = activeURL, !canvas.selected.isEmpty else { return }
        let board = canvas.board.selection(canvas.selected)
        guard let name = askName("Keep selection as an idea",initial:"Saved thought") else { return }
        afterSaving { self.copyBoard(board,from:source,name:name) }
    }
    private func copyBoard(_ board: Board, from source: URL, name: String) {
        guard !isBusy else { return }; isBusy = true; saveWork?.cancel()
        io.async {
            do {
                var copy = board; copy.id = UUID()
                let url = try self.library.copy(copy,from:source,name:name)
                DispatchQueue.main.async { self.isBusy = false; self.loadIdea(url); self.refreshShelf() }
            } catch { DispatchQueue.main.async { self.isBusy = false; self.showError(error) } }
        }
    }
    @objc func revealFolder() { NSWorkspace.shared.open(library.root) }
    @objc func revealCard(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Choose a folder for your Unfinished, Finished and Archive ideas."
        if panel.runModal() == .OK, let url = panel.url { afterSaving { self.openLibrary(url) } }
    }
    @objc func importImageFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff,.heic,.gif]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, activeURL != nil, !isBusy else { return }
        let boardID = canvas.board.id
        let point = canvas.board.viewport.world(Point(canvas.bounds.midX-250,canvas.bounds.midY-120))
        io.async {
            do {
                let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size <= 32*1024*1024 else { throw BoardError.invalidData }
                let data = try Data(contentsOf:url)
                DispatchQueue.main.async { guard self.canvas.board.id == boardID else { return }; self.importImage(data,ext:url.pathExtension,at:point) }
            } catch { DispatchQueue.main.async { self.showError(error) } }
        }
    }
    @objc func showScreens() {
        let menu = NSMenu()
        for (i,screen) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title:"\(screenID(screen) == onScreen ? "✓ " : "")\(screen.localizedName) — \(Int(screen.frame.width)) × \(Int(screen.frame.height))",action:#selector(pickScreen(_:)),keyEquivalent:"")
            item.tag = i; item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:NSEvent.mouseLocation,in:nil)
    }
    @objc func pickScreen(_ sender: NSMenuItem) { guard NSScreen.screens.indices.contains(sender.tag) else { return }; move(to:NSScreen.screens[sender.tag]); showBoard() }
    @objc func bringHere() { if let screen = NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) { move(to:screen) }; showBoard() }
    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    private func move(to screen: NSScreen) { canvas.finishGesture(); onScreen = screenID(screen); window.setFrame(screen.visibleFrame,display:true) }
    @objc func displaysChanged() {
        let screen = NSScreen.screens.first(where:{screenID($0) == onScreen}) ?? NSScreen.main
        if let screen { move(to:screen) }
    }
    @objc func willSleep() { if usingDesktop { hideBoard() } else { canvas.finishEditing(); canvas.finishGesture(); saveNow() } }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(cropImage) { return !isBusy && canvas.selected.count == 1 && canvas.board.images.contains {canvas.selected.contains($0.id) && !$0.locked && $0.vectorAsset == nil} }
        if menuItem.action == #selector(restoreImage) { return !isBusy && canvas.board.images.contains {canvas.selected.contains($0.id) && !$0.locked && $0.crop != nil} }
        return true
    }
    @objc func insertLaTeX() { presentTeX(kind:.latex) }
    @objc func insertTikZ() { presentTeX(kind:.tikz) }
    @objc func editSelectedTeX() {
        if let item = canvas.board.images.first(where: {canvas.selected.contains($0.id) && $0.tex != nil}) { editTeX(item.id) }
    }
    private func editTeX(_ id: UUID) {
        guard let item = canvas.board.images.first(where: {$0.id == id}), let source = item.tex else { return }
        presentTeX(kind:source.kind,existing:item)
    }
    private func presentTeX(kind: TeXKind, existing: BoardImage? = nil, initialCode: String? = nil) {
        guard !isBusy, !renderingTeX, let package = activeURL else { return }
        canvas.finishEditing(); canvas.finishGesture()
        guard let source = TeXEditor.edit(kind:kind,initial:initialCode ?? existing?.tex?.code ?? texDrafts[kind]) else { return }
        texDrafts[kind] = source.code
        let boardID = canvas.board.id
        let point = canvas.board.viewport.world(Point(canvas.bounds.midX-220,canvas.bounds.midY-100))
        renderingTeX = true; pendingImports += 1; saveLabel.stringValue = "Rendering…"
        typesetting.async {
            let result = Result { try TeXCompiler.compile(source) }
            self.io.async {
                let stored = result.flatMap { render in Result { () -> (String,String,Double,Double) in
                    let png = try self.library.importAsset(data:render.png,extension:"png",to:package)
                    let pdf = try self.library.importAsset(data:render.pdf,extension:"pdf",to:package)
                    return (png,pdf,render.width,render.height)
                } }
                DispatchQueue.main.async {
                    self.renderingTeX = false; self.pendingImports -= 1
                    guard self.canvas.board.id == boardID, self.activeURL == package else { self.saveNow(); return }
                    switch stored {
                    case .success(let values):
                        if let existing, !self.canvas.board.images.contains(where: {$0.id == existing.id}) { self.updateLabels(); self.saveNow(); return }
                        self.canvas.checkpoint()
                        if let existing, let i = self.canvas.board.images.firstIndex(where: {$0.id == existing.id}) {
                            let old = self.canvas.board.images[i].frame
                            let height = old.width*values.3/values.2
                            self.canvas.board.images[i].asset = values.0; self.canvas.board.images[i].vectorAsset = values.1; self.canvas.board.images[i].tex = source
                            self.canvas.board.images[i].frame.height = height
                            for j in self.canvas.board.ink.indices where self.canvas.board.ink[j].imageID == existing.id {
                                self.canvas.board.ink[j].points = self.canvas.board.ink[j].points.map {Point($0.x,old.y+($0.y-old.y)*height/old.height)}
                            }
                        } else {
                            let width = min(600,max(180,values.2*2.2))
                            var item = BoardImage(asset:values.0,frame:Rect(point.x,point.y,width,width*values.3/values.2)); item.tex = source; item.vectorAsset = values.1
                            self.canvas.board.images.append(item); self.canvas.selected = [item.id]
                        }
                        self.canvas.reindex(); self.canvas.images.clear(); self.canvas.needsDisplay = true; self.edited()
                    case .failure(let error):
                        self.updateLabels(); self.showError(error)
                        if self.afterSave == nil { self.presentTeX(kind:kind,existing:existing,initialCode:source.code) }
                    }
                    if self.afterSave != nil { self.saveNow() }
                }
            }
        }
    }
    @objc func exportWorkspace() {
        canvas.finishEditing(); canvas.finishGesture()
        guard let content = window.contentView, !exporting else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = titleLabel.stringValue+" workspace.png"
        panel.message = "Include the shelf and controls. The surrounding desktop is left out."
        guard panel.runModal() == .OK, let url = panel.url,
              let rep = content.bitmapImageRepForCachingDisplay(in:content.bounds) else { return }
        let background = canvas.board.background; canvas.board.background = "paper"
        content.cacheDisplay(in:content.bounds,to:rep)
        canvas.board.background = background; canvas.needsDisplay = true
        exporting = true
        io.async {
            let result = Result { () -> Void in
                guard let data = rep.representation(using:.png,properties:[:]) else { throw BoardError.invalidData }
                try data.write(to:url,options:.atomic)
            }
            DispatchQueue.main.async { self.exporting = false; if case .failure(let error) = result { self.showError(error) } }
        }
    }
    @objc func exportPNG() { exportDocument(pdf:false) }
    @objc func exportPDF() { exportDocument(pdf:true) }
    private func exportDocument(pdf: Bool) {
        canvas.finishEditing(); canvas.finishGesture()
        guard let package = activeURL, !exporting else { return }
        let board = canvas.selected.isEmpty ? canvas.board : canvas.board.selection(canvas.selected)
        let panel = NSSavePanel(); panel.allowedContentTypes = pdf ? [.pdf] : [.png]
        panel.nameFieldStringValue = titleLabel.stringValue+(canvas.selected.isEmpty ? "" : " selection")+(pdf ? ".pdf" : ".png")
        panel.message = canvas.selected.isEmpty ? "Export all content with a clean paper background." : "Export the selected content with a clean paper background."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true; saveLabel.stringValue = "Exporting…"
        io.async {
            let result = Result { () -> Void in
                let data = try pdf ? BoardRenderer.pdf(board,package:package) : BoardRenderer.png(board,package:package)
                try data.write(to:url,options:.atomic)
            }
            DispatchQueue.main.async { self.exporting = false; self.updateLabels(); if case .failure(let error) = result { self.showError(error) } }
        }
    }
    private func copySelection() {
        canvas.finishEditing(); canvas.finishGesture()
        guard let package = activeURL, !canvas.selected.isEmpty, !exporting else { return }
        let board = canvas.board.selection(canvas.selected); exporting = true
        io.async {
            let result = Result { try BoardRenderer.png(board,package:package) }
            DispatchQueue.main.async {
                self.exporting = false
                switch result { case .success(let data): NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType:.png)
                case .failure(let error): self.showError(error) }
            }
        }
    }
    @objc func saveCheckpoint() {
        afterSaving {
            guard let source = self.activeURL else { return }; self.isBusy = true
            self.io.async {
                let result = Result { try self.library.checkpoint(source) }
                DispatchQueue.main.async {
                    self.isBusy = false
                    switch result {
                    case .success: self.saveLabel.stringValue = "Checkpoint saved"
                    case .failure(let error): self.showError(error)
                    }
                }
            }
        }
    }
    @objc func showRecoveryHistory() {
        guard let source = activeURL else { return }; presentRecoveryHistory(source)
    }
    @objc private func recoverCard(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? URL else { return }; presentRecoveryHistory(source)
    }
    private func presentRecoveryHistory(_ source: URL) {
        guard !isBusy else { return }
        canvas.finishEditing(); canvas.finishGesture(); saveWork?.cancel(); isBusy = true
        io.async {
            let result = Result { try self.library.history(source) }
            DispatchQueue.main.async {
                switch result {
                case .failure(let error): self.isBusy = false; self.showError(error); self.saveNow()
                case .success(let snapshots):
                    let alert = NSAlert(); alert.messageText = "Recovery history · "+source.deletingPathExtension().lastPathComponent
                    if snapshots.isEmpty {
                        alert.informativeText = "No snapshots yet. Choose File → Save checkpoint to keep this version. Automatic snapshots are kept as you edit, at least five minutes apart."
                        alert.addButton(withTitle:"Done"); alert.runModal(); self.isBusy = false; self.saveNow(); return
                    }
                    alert.informativeText = "Choose a saved version. It opens as a separate recovered idea. Up to 20 snapshots are kept within a 64 MiB history budget; image assets are shared."
                    let picker = NSPopUpButton(frame:NSRect(x:0,y:0,width:360,height:28),pullsDown:false)
                    let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
                    for (index,snapshot) in snapshots.enumerated() { picker.addItem(withTitle:"\(index+1). \(formatter.string(from:snapshot.date))") }
                    picker.setAccessibilityLabel("Saved version"); alert.accessoryView = picker
                    alert.addButton(withTitle:"Recover as copy"); alert.addButton(withTitle:"Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { self.isBusy = false; self.saveNow(); return }
                    let snapshot = snapshots[picker.indexOfSelectedItem]
                    self.io.async {
                        let recovered = Result { try self.library.recoverSnapshot(snapshot.filename,from:source) }
                        DispatchQueue.main.async {
                            self.isBusy = false
                            switch recovered {
                            case .success(let url): self.refreshShelf(); self.afterSaving { self.loadIdea(url) }
                            case .failure(let error): self.showError(error); self.saveNow()
                            }
                        }
                    }
                }
            }
        }
    }
    @objc func recoverPrevious() {
        guard let source = activeURL, !isBusy else { return }
        canvas.finishEditing(); canvas.finishGesture(); isBusy = true
        // Read the previous save before a new save can replace it. Recovery creates a separate file.
        saveWork?.cancel()
        io.async {
            let result = Result { try self.library.recoverPrevious(source) }
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let recovered): self.refreshShelf(); self.afterSaving { self.loadIdea(recovered) }
                case .failure(let error): self.showError(error); self.saveNow()
                }
            }
        }
    }
    @objc func trySamples() {
        guard !isDemo else { return }
        afterSaving { self.openLibrary(self.demoRoot) }
    }
    @objc func returnToIdeas() {
        guard isDemo else { return }
        afterSaving { self.openLibrary(self.root) }
    }
    @objc func captureScreenshot() {
        guard !isBusy, activeURL != nil else { return }
        let documentID = canvas.board.id
        let point = canvas.board.viewport.world(Point(canvas.bounds.midX-250,canvas.bounds.midY-150))
        hideBoard(); isBusy = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
        process.arguments = ["-i","-o","-x",url.path]
        process.terminationHandler = { _ in
            let data = try? Data(contentsOf:url); try? FileManager.default.removeItem(at:url)
            DispatchQueue.main.async {
                self.isBusy = false; self.showBoard()
                if let data, self.canvas.board.id == documentID { self.importImage(data,ext:"png",at:point) }
            }
        }
        do { try process.run() } catch { isBusy = false; showBoard(); showError(error) }
    }
    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Your work needs attention"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle:"OK"); alert.runModal()
    }
    @objc func showHelp() {
        let alert = NSAlert(); alert.messageText = "Whiteboard · native preview"
        alert.informativeText = "⇧⌘B show / hide\nP pen · H highlighter · E eraser · V select · T text\nAuto shapes: draw with the pen and lift to recognise. Undo restores the original ink.\nHold Shift with the pen to keep freehand, or turn Auto shapes off.\nL line · A arrow · R rectangle · O ellipse\nHold Shift for equal sides or 45° angles. Escape cancels a shape.\nSelect a screenshot, then C to crop. Return applies; Escape cancels.\nEdit → Restore full image removes its crop. Ink stays in place.\nHold ⌘⇧Space to use the desktop; release to return.\nRight-drag erases ink. Scroll for more space.\nPinch or ⌘ scroll to zoom. Option-drag pans.\n⌘Z undo · ⇧⌘Z redo · ⌘V paste · Return rename\n\nSelect images or ink to move them. Drag an image’s bottom-right handle to resize its annotations together. ⌘D duplicates; ⌘1 fits all content; ⌘C copies a selection as PNG. Control-click a shelf file to pin, reorder, change status or archive. Demo opens a separate editable sample workspace; My ideas brings you back.\n\nAutosaves after edits. Handwriting transcription, thumbnails and drag-to-status are planned; see docs/IMPLEMENTATION.md."
        alert.addButton(withTitle:"Got it"); alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        canvas.finishEditing(); canvas.finishGesture()
        if saveBlocked { showError(BoardError.conflict); return .terminateCancel }
        if savedRevision == revision && !isSaving && pendingImports == 0 { return .terminateNow }
        terminationPending = true
        afterSave = { self.terminationPending = false; NSApp.reply(toApplicationShouldTerminate:true) }; saveNow(); return .terminateLater
    }
}
