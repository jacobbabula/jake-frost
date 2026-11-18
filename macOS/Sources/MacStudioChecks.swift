import AppKit

@MainActor func runMacStudioChecks() -> Bool {
    _=NSApplication.shared
    let suite="io.jakefrost.studio-tests."+UUID().uuidString
    guard let settings=UserDefaults(suiteName:suite) else{return false}
    defer {settings.removePersistentDomain(forName:suite)}
    let desktop=SnowWorld(),workshop=MacWorkshop()
    desktop.setDesktop(size:CGSize(width:640,height:420),edges:[])
    workshop.configure(settings:settings,displayID:7);workshop.sync(world:desktop)
    let weather=MacWeatherControls(settings:settings,onChange:{})
    let studio=MacStudio(menu:{
        let root=NSMenu()
        weather.append(to:root);workshop.appendMenu(to:root)
        return root
    })
    workshop.onEditingChanged={ [weak studio,weak workshop] in studio?.setWorkshopEditing(workshop?.editing == true) }
    defer {workshop.onEditingChanged=nil;studio.close()}
    studio.show()
    guard let view=studio.panel.contentView else{return false}
    func controls(_ element:NSView)->[NSView]{[element]+element.subviews.flatMap(controls)}
    func click(_ title:String)->Bool {
        guard let button=controls(view).compactMap({$0 as? NSButton}).first(where:{$0.title==title}),
              button.isEnabled else{return false}
        button.performClick(nil);return true
    }
    guard let tabs=controls(view).compactMap({$0 as? NSSegmentedControl}).first,let action=tabs.action,
          controls(view).compactMap({$0 as? NSButton}).contains(where:{$0.title=="Snow…" && $0.isEnabled}) else{return false}
    func tab(_ i:Int){tabs.selectedSegment=i;_=NSApp.sendAction(action,to:tabs.target,from:tabs)}
    tab(1)
    let at=studio.panel.frame
    guard click("Roll a snowball"),workshop.editing,studio.panel.isCollapsed,studio.panel.isVisible,
          abs(studio.panel.frame.maxY-at.maxY)<1,abs(studio.panel.frame.minX-at.minX)<1 else {
        print("FAIL: studio snow tool did not fold the visible panel in place");return false
    }
    workshop.finishEditing()
    guard !studio.panel.isCollapsed,studio.panel.frame.size==at.size,tabs.selectedSegment==1 else{return false}
    tab(2)
    guard click("Decorate a tree…"),workshop.designedTree != nil,
          let editor=NSApp.windows.first(where:{$0.title=="Decorate a tree" && $0.isVisible}) else{return false}
    editor.close()
    print("PASS: main Mac studio dispatches real desktop and tree commands and folds in place while a tool is active")
    return true
}
