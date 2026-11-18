import AppKit

@MainActor enum MacTreeLights {
    static let paletteNames = ["Candlelight", "Festive", "Aurora"]
    private static let paletteHex: [[Int]] = [
        [0xFFD678,0xFFF1C3,0xFFAF57], [0xF56570,0x70DAA1,0x66C6F8,0xFFD36C,0xCF91FF],
        [0x7EE9D7,0x8ABBF5,0xC49AF6,0xA1EAA8]
    ]
    private static func color(_ value:Int)->CGColor {
        let red=CGFloat(value>>16)/255
        let green=CGFloat((value>>8)&255)/255
        let blue=CGFloat(value&255)/255
        return CGColor(red:red,green:green,blue:blue,alpha:1)
    }
    private static let colors:[[CGColor]] = paletteHex.map { $0.map(color) }
    private static let positions:[CGPoint] = [(-8,-20),(-3,-16),(3,-13),(10,-12),(-14,-5),(-7,0),(1,3),(8,3),(16,2),
                                               (-22,11),(-14,16),(-5,19),(3,21),(12,21),(21,18)].map {CGPoint(x:$0.0,y:$0.1)}
    private static let baubles:[CGPoint] = [(-7,-10),(8,-5),(-16,8),(4,11),(-9,24),(18,24)].map{CGPoint(x:$0.0,y:$0.1)}
    private static let wire:CGPath = {
        let path=CGMutablePath()
        for row in [0..<4,4..<9,9..<15] {
            path.move(to:positions[row.lowerBound])
            for i in row.dropFirst(){path.addLine(to:positions[i])}
        }
        return path
    }()
    private static let copper=CGColor(red:0.60,green:0.46,blue:0.23,alpha:1)
    private static let snow=CGColor(gray:1,alpha:0.93)
    static func brightness(_ time:TimeInterval,_ index:Int)->CGFloat {
        let phase=time*(2.35+Double(index%3)*0.24)+Double(index)*2.17
        return CGFloat(0.56+0.44*(0.5+0.5*sin(phase)))
    }
    static func draw(trim:Int,palette:Int,time:TimeInterval?,in c:CGContext) {
        let shades=colors[colors.indices.contains(palette) ? palette:1]
        c.saveGState();defer{c.restoreGState()}
        if trim & 2 != 0 {
            c.setStrokeColor(copper);c.setLineWidth(0.85);c.setLineJoin(.round);c.addPath(wire);c.strokePath()
            for (index,p) in positions.enumerated() {
                let glow=(trim & 4 != 0 ? time.map{brightness($0,index)}:nil) ?? 1
                c.setFillColor(shades[index%shades.count])
                c.setAlpha(0.22*glow);c.fillEllipse(in:CGRect(x:p.x-3.0,y:p.y-1.8,width:6.0,height:6.4))
                c.setAlpha(glow);c.fillEllipse(in:CGRect(x:p.x-1.15,y:p.y,width:2.3,height:3.6))
                c.setAlpha(1);c.setFillColor(snow);c.fillEllipse(in:CGRect(x:p.x-0.65,y:p.y+0.5,width:0.75,height:1.4))
            }
        }
        if trim & 1 != 0 {
            for (index,p) in baubles.enumerated() {
                c.setFillColor(copper);c.fill(CGRect(x:p.x-0.65,y:p.y-3.4,width:1.3,height:1.9))
                c.setFillColor(shades[(index+2)%shades.count]);c.fillEllipse(in:CGRect(x:p.x-2.5,y:p.y-2.5,width:5,height:5))
                c.setFillColor(snow);c.fillEllipse(in:CGRect(x:p.x-1.4,y:p.y-1.6,width:1.3,height:1.05))
            }
        }
    }
}

@MainActor private final class MacTreePreview:NSView {
    weak var workshop:MacWorkshop?
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.89,green:0.95,blue:0.97,alpha:1).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill()
        workshop?.drawPreview(in:bounds)
    }
}

@MainActor final class MacTreeEditor:NSObject {
    private weak var workshop:MacWorkshop?
    let panel=AnchoredPanel(contentRect:NSRect(x:0,y:0,width:384,height:384),title:"Decorate a tree")
    private let choice=NSPopUpButton(frame:.zero,pullsDown:false)
    private let palette=NSPopUpButton(frame:.zero,pullsDown:false)
    private let ornaments=NSPopUpButton(frame:.zero,pullsDown:false)
    private let preview=MacTreePreview()
    private let count=NSTextField(labelWithString:"")
    private let baubles=NSButton(checkboxWithTitle:"Baubles",target:nil,action:nil)
    private let lights=NSButton(checkboxWithTitle:"Lights",target:nil,action:nil)
    private let twinkle=NSButton(checkboxWithTitle:"Twinkle",target:nil,action:nil)
    private lazy var remove=NSButton(title:"Remove last",target:self,action:#selector(unhang))
    private lazy var hang=NSButton(title:"Hang ornament",target:self,action:#selector(attach))
    private lazy var pick=NSButton(title:"Pick on desktop",target:self,action:#selector(pickTree))
    private lazy var apply=NSButton(title:"Apply to a tree…",target:self,action:#selector(applyToTree))
    private let kinds=WorkshopKind.allCases.filter{$0.giftOrnamentID != nil}
    init(workshop:MacWorkshop) {
        self.workshop=workshop
        super.init()
        panel.finishTool={ [weak workshop] in workshop?.finishEditing() }
        preview.workshop=workshop
        palette.addItems(withTitles:MacTreeLights.paletteNames);ornaments.addItems(withTitles:kinds.map(\.rawValue))
        ornaments.selectItem(withTitle:WorkshopKind.bauble.rawValue)
        choice.setAccessibilityLabel("Tree to decorate");palette.setAccessibilityLabel("Tree colors")
        ornaments.setAccessibilityLabel("Ornament")
        choice.target=self;choice.action=#selector(switchTree);palette.target=self;palette.action=#selector(updateDesign)
        for button in [baubles,lights,twinkle]{button.target=self;button.action=#selector(updateDesign)}
        let plant=NSButton(title:"Plant another",target:self,action:#selector(plantTree))
        let defaults=NSButton(title:"Use for new trees",target:self,action:#selector(saveDefaults))
        func row(_ items:[NSView])->NSStackView {
            let r=NSStackView(views:items);r.orientation = .horizontal;r.spacing=6;r.alignment = .centerY;return r
        }
        let heading=NSTextField(labelWithString:"Tree to decorate");heading.font = .boldSystemFont(ofSize:13)
        let previewColumn=NSStackView(views:[palette,baubles,lights,twinkle])
        previewColumn.orientation = .vertical;previewColumn.alignment = .leading;previewColumn.spacing=6
        let drawing=row([preview,previewColumn]);drawing.spacing=16
        NSLayoutConstraint.activate([preview.widthAnchor.constraint(equalToConstant:136),preview.heightAnchor.constraint(equalToConstant:123)])
        let branch=NSTextField(labelWithString:"Ornaments");branch.font = .boldSystemFont(ofSize:13)
        count.textColor = .secondaryLabelColor;count.font = .systemFont(ofSize:11)
        let stack=NSStackView(views:[heading,row([choice,pick,plant]),drawing,branch,row([ornaments,hang,remove]),count,row([defaults,apply])])
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=11
        stack.translatesAutoresizingMaskIntoConstraints=false
        if let content=panel.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:16),
                                         stack.topAnchor.constraint(equalTo:content.topAnchor,constant:15),
                                         stack.trailingAnchor.constraint(lessThanOrEqualTo:content.trailingAnchor,constant:-12)])
        }
        panel.center()
    }
    func show(){panel.expand();refresh();NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)}
    func setPicking(_ value:Bool){panel.setWorkshopEditing(value)}
    func redrawLights(){if panel.isVisible && !panel.isCollapsed {preview.needsDisplay=true}}
    func refresh() {
        guard let owner=workshop else{return}
        let trees=owner.trees,tree=owner.designedTree
        choice.removeAllItems()
        for (i,t) in trees.enumerated() {
            choice.addItem(withTitle:"Tree \(i+1)");choice.lastItem?.representedObject=t.id.uuidString
            if t.id==tree?.id {choice.selectItem(at:i)}
        }
        if tree==nil {choice.select(nil)}
        let trim=tree?.trim ?? 7
        palette.selectItem(at:tree?.displayedTreePalette ?? 1)
        baubles.state=trim & 1 != 0 ? .on:.off; lights.state=trim & 2 != 0 ? .on:.off
        twinkle.state=trim & 4 != 0 ? .on:.off
        twinkle.isEnabled=tree != nil && owner.twinkleEnabled && lights.state == .on
        twinkle.toolTip=owner.twinkleEnabled ? nil:"Enable Twinkle string and tree lights in the Decorate menu."
        let n=tree.map{t in owner.pieces.filter{$0.attachment?.tree==t.id}.count} ?? 0
        count.stringValue=tree==nil ? "Plant or select a tree." : "\(n) hand-hung ornament\(n==1 ? "" : "s")"
        for control:NSControl in [palette,baubles,lights,hang,ornaments,apply]{control.isEnabled=tree != nil}
        pick.isEnabled = !trees.isEmpty;remove.isEnabled=n>0
        preview.needsDisplay=true
    }
    @objc private func switchTree(){if let s=choice.selectedItem?.representedObject as? String,let id=UUID(uuidString:s){workshop?.selectTree(id)}}
    @objc private func updateDesign(){
        let mask=(baubles.state == .on ? 1:0)|(lights.state == .on ? 2:0)|(twinkle.state == .on ? 4:0)
        workshop?.setTreeDesign(trim:mask,color:palette.indexOfSelectedItem)
    }
    @objc private func attach(){let i=ornaments.indexOfSelectedItem;if kinds.indices.contains(i){_=workshop?.hang(kinds[i])}}
    @objc private func unhang(){workshop?.unhang()}
    @objc private func plantTree(){workshop?.plantForEditor()}
    @objc private func pickTree(){workshop?.pickTreeOnDesktop()}
    @objc private func applyToTree(){workshop?.pickTreeOnDesktop(applyDesign:true)}
    @objc private func saveDefaults(){workshop?.rememberTreeDefaults()}
}
