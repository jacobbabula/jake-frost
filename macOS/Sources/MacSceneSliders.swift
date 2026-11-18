import AppKit

@MainActor final class MacSceneSliders: NSObject {
    typealias Row=(label:String,key:String,suffix:String,initial:Int,minimum:Int,maximum:Int)
    private final class Setting {
        let key:String, suffix:String
        let slider:NSSlider, value=NSTextField(labelWithString:"")
        init(key:String,suffix:String,value:Int,minimum:Int,maximum:Int) {
            self.key=key;self.suffix=suffix
            slider=NSSlider(value:Double(value),minValue:Double(minimum),maxValue:Double(maximum),target:nil,action:nil)
        }
        var current:Int {Int(slider.doubleValue.rounded())}
    }
    private var fields=[Setting]()
    func open(_ title:String,rows:[Row],save:([String:Int])->Void) {
        let form=NSStackView();form.orientation = .vertical;form.alignment = .leading;form.spacing=8
        for (label,key,suffix,initial,lo,hi) in rows {
            let field=Setting(key:key,suffix:suffix,value:initial,minimum:lo,maximum:hi)
            fields.append(field);field.slider.target=self;field.slider.action=#selector(changed(_:))
            field.slider.isContinuous=true;field.slider.setAccessibilityLabel(label)
            field.value.alignment = .right;field.value.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
            field.value.stringValue=String(field.current)+suffix
            let name=NSTextField(labelWithString:label);name.font = .systemFont(ofSize:13,weight:.medium)
            form.addArrangedSubview(name)
            let row=NSStackView(views:[field.slider,field.value]);row.orientation = .horizontal;row.spacing=7
            form.addArrangedSubview(row)
            field.slider.widthAnchor.constraint(equalToConstant:222).isActive=true
            field.value.widthAnchor.constraint(equalToConstant:58).isActive=true
        }
        defer{fields.removeAll()}
        let prompt=NSAlert();prompt.messageText=title;prompt.addButton(withTitle:"Apply");prompt.addButton(withTitle:"Cancel")
        form.frame=NSRect(origin:.zero,size:form.fittingSize);prompt.accessoryView=form
        NSApp.activate(ignoringOtherApps:true)
        if prompt.runModal() == .alertFirstButtonReturn {
            save(Dictionary(uniqueKeysWithValues:fields.map{($0.key,$0.current)}))
        }
    }
    @objc private func changed(_ slider:NSSlider){
        guard let field=fields.first(where:{$0.slider === slider}) else{return}
        field.value.stringValue=String(field.current)+field.suffix
    }
}
