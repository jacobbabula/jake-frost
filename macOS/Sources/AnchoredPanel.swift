import AppKit

/// A compact title bar can stay at the same spot on the desktop while its form is folded away.
@MainActor final class AnchoredPanel: NSPanel {
    private var fullContent: NSView?
    private var fullSize = NSSize.zero
    private var previousLevel = NSWindow.Level.normal
    private var previousHidesOnDeactivate = false
    private weak var previousFocus: NSResponder?
    private var restoreAccessory: NSTitlebarAccessoryViewController?
    private var foldedForTool = false
    var isCollapsed: Bool { fullContent != nil }

    init(contentRect: NSRect, title: String) {
        super.init(contentRect:contentRect, styleMask:[.titled,.closable,.miniaturizable], backing:.buffered, defer:false)
        self.title = title
        isReleasedWhenClosed = false
        if let yellow = standardWindowButton(.miniaturizeButton) {
            yellow.target = self; yellow.action = #selector(performMiniaturize(_:))
            yellow.toolTip = "Minimize in place (⌘M)"
        }
    }
    required init?(coder:NSCoder) { fatalError("Programmatic window") }

    override func performMiniaturize(_ sender:Any?) { isCollapsed ? expand() : collapse() }
    override func miniaturize(_ sender:Any?) { performMiniaturize(sender) }
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.intersection([.command,.option,.control,.shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "m" {
            performMiniaturize(nil)
            return true
        }
        return super.performKeyEquivalent(with:event)
    }

    private func setSize(_ size:NSSize, left:CGFloat, top:CGFloat) {
        setFrame(NSRect(x:left,y:top-size.height,width:size.width,height:size.height),display:true)
    }
    private func collapse() {
        guard let form = contentView else { return }
        if let editor = firstResponder as? NSTextView, editor.isFieldEditor, let control = editor.delegate as? NSControl {
            control.validateEditing()
            previousFocus = control
        } else { previousFocus = firstResponder }
        guard makeFirstResponder(nil) else { return }
        let original = frame
        fullSize = original.size; fullContent = form
        previousLevel = level; previousHidesOnDeactivate = hidesOnDeactivate
        // Keep constraints and controls with the original content. Nothing in the form is rebuilt.
        contentView = NSView(frame:.zero)
        let button = NSButton(title:"Restore",target:self,action:#selector(restorePanel(_:)))
        button.bezelStyle = .inline
        button.setAccessibilityLabel("Restore " + title)
        button.toolTip = "Restore in place (⌘M)"
        button.sizeToFit()
        let accessory = NSTitlebarAccessoryViewController()
        let holder = NSView(frame:NSRect(x:0,y:0,width:button.frame.width+12,height:24))
        button.frame.origin = NSPoint(x:2,y:(holder.frame.height-button.frame.height)/2)
        holder.addSubview(button); accessory.view = holder; accessory.layoutAttribute = .right
        addTitlebarAccessoryViewController(accessory); restoreAccessory = accessory
        hidesOnDeactivate = false; level = .floating
        let compact = frameRect(forContentRect:NSRect(x:0,y:0,width:min(218,fullSize.width),height:1)).size
        setSize(compact,left:original.minX,top:original.maxY)
        standardWindowButton(.miniaturizeButton)?.toolTip = "Restore in place (⌘M)"
    }
    @objc private func restorePanel(_ sender:Any?) { expand() }
    func setWorkshopEditing(_ active:Bool) {
        if active {
            guard isVisible, !isCollapsed, !isMiniaturized else { return }
            collapse()
            foldedForTool = isCollapsed
        } else if foldedForTool {
            foldedForTool = false
            if isVisible { expand() }
        }
    }
    func expand() {
        guard let form = fullContent else { return }
        foldedForTool = false
        let anchor = frame
        if let accessory = restoreAccessory, let index = titlebarAccessoryViewControllers.firstIndex(where:{ $0 === accessory }) {
            removeTitlebarAccessoryViewController(at:index)
        }
        restoreAccessory = nil
        contentView = form; fullContent = nil
        level = previousLevel; hidesOnDeactivate = previousHidesOnDeactivate
        setSize(fullSize,left:anchor.minX,top:anchor.maxY)
        if let focus = previousFocus { makeFirstResponder(focus) }
        previousFocus = nil
        standardWindowButton(.miniaturizeButton)?.toolTip = "Minimize in place (⌘M)"
    }
}

@MainActor func runAnchoredPanelChecks() -> Bool {
    _ = NSApplication.shared
    let win = AnchoredPanel(contentRect:CGRect(x:0,y:0,width:380,height:180),title:"Gift draft")
    let note = NSTextField(frame:CGRect(x:12,y:22,width:280,height:24))
    note.stringValue = "First snow"
    win.contentView?.addSubview(note); win.center(); win.makeKeyAndOrderFront(nil)
    defer { win.close() }
    let start = win.frame, form = win.contentView
    win.makeFirstResponder(note)
    if let editor = note.currentEditor() { editor.string = "First snow at the cabin" }
    else { note.stringValue = "First snow at the cabin" }
    func anchored(_ rect:NSRect,to old:NSRect) -> Bool {
        abs(rect.minX-old.minX)<1 && abs(rect.maxY-old.maxY)<1
    }
    guard let yellow = win.standardWindowButton(.miniaturizeButton) else { return false }
    yellow.performClick(nil)
    let folded = win.frame
    guard win.isCollapsed, win.isVisible, !win.isMiniaturized, anchored(folded,to:start),
          folded.height < start.height/2, folded.width < start.width else {
        print("FAIL: yellow minimize did not leave an anchored compact panel"); return false
    }
    let button = win.titlebarAccessoryViewControllers.last?.view.subviews.compactMap { $0 as? NSButton }.first
    button?.performClick(nil)
    guard !win.isCollapsed, win.contentView === form, note.stringValue == "First snow at the cabin",
          anchored(win.frame,to:start), win.frame.size == start.size else {
        print("FAIL: Restore did not retain the form, draft and geometry"); return false
    }
    guard let shortcut=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,
            timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:win.windowNumber,
            context:nil,characters:"m",charactersIgnoringModifiers:"m",isARepeat:false,keyCode:46),
          win.performKeyEquivalent(with:shortcut), win.isCollapsed else { return false }
    let relocated = NSPoint(x:win.frame.minX+14,y:win.frame.maxY-12)
    win.setFrameTopLeftPoint(relocated); let moved = win.frame
    win.expand()
    guard anchored(win.frame,to:moved), win.contentView === form, win.frame.size == start.size else { return false }
    print("PASS: yellow button and Command-M fold in place; Restore preserves typed content and the panel's top-left anchor")
    let alreadyFolded=AnchoredPanel(contentRect:CGRect(x:0,y:0,width:370,height:150),title:"Already folded")
    let closed=AnchoredPanel(contentRect:CGRect(x:0,y:0,width:320,height:140),title:"Closed")
    defer { alreadyFolded.close(); closed.close() }
    alreadyFolded.center(); alreadyFolded.orderFront(nil); alreadyFolded.performMiniaturize(nil)
    win.makeKeyAndOrderFront(nil)
    let toolAnchor=win.frame, hiddenSize=closed.frame.size
    let workshop=MacWorkshop()
    workshop.onEditingChanged = {
        for panel in [win,alreadyFolded,closed] { panel.setWorkshopEditing(workshop.editing) }
    }
    defer { workshop.onEditingChanged=nil }
    let menu=NSMenu()
    workshop.appendMenu(to:menu)
    guard let tools=menu.items.compactMap({$0.submenu}).first(where:{$0.item(withTitle:"Pile snow") != nil}),
          let tool=tools.item(withTitle:"Pile snow"), let select=tool.action else { return false }
    _ = NSApplication.shared.sendAction(select,to:tool.target,from:tool)
    guard win.isCollapsed,anchored(win.frame,to:toolAnchor),alreadyFolded.isCollapsed,
          !closed.isVisible,!closed.isCollapsed else { print("FAIL: starting a workshop tool did not fold exactly the visible open forms");return false }
    win.expand()
    workshop.placeSled()
    guard win.isCollapsed,anchored(win.frame,to:toolAnchor) else {print("FAIL: selecting another tool did not refold the open panel");return false}
    menu.removeAllItems(); workshop.appendMenu(to:menu)
    guard let stop=menu.items.compactMap({$0.submenu}).compactMap({$0.item(withTitle:"Done playing")}).first,
          let end=stop.action else {return false}
    _ = NSApplication.shared.sendAction(end,to:stop.target,from:stop)
    guard !win.isCollapsed,anchored(win.frame,to:toolAnchor),win.frame.size==toolAnchor.size,
          note.stringValue=="First snow at the cabin",alreadyFolded.isCollapsed,
          !closed.isVisible,closed.frame.size==hiddenSize else { print("FAIL: Done did not restore only tool-folded forms");return false }
    workshop.beginPiling();win.close();workshop.finishEditing()
    guard !win.isVisible else {print("FAIL: Done reopened a panel closed during editing");return false}
    print("PASS: choosing a desktop tool folds the gift draft in place; Done restores it and respects closed or manually folded panels")
    return true
}
