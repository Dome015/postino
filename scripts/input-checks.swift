import AppKit

@main
struct InputChecks {
    static func main() {
        let fields: [NSTextField] = [InputField(), SecureInputField(), InputSearchField()]
        var checks = 0
        for field in fields {
            precondition(field.isEditable && field.isSelectable, "Replacing a cell must preserve typing and selection")
            precondition(!field.isBordered && !field.isBezeled, "Native inputs leave their background to the shared glass surface")
            precondition(field.constraints.contains { $0.firstAttribute == .height && $0.constant == 28 }, "Every input must be 28pt high")
            checks += 3
            for font in [NSFont.systemFont(ofSize: 13), NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), NSFont.systemFont(ofSize: 13, weight: .semibold)] {
                field.font = font
                for width: CGFloat in [100, 320, 800] {
                    let bounds = NSRect(x: 0, y: 0, width: width, height: 28)
                    let cell = field.cell as! NSTextFieldCell
                    let rect = (cell as? NSSearchFieldCell)?.searchTextRect(forBounds: bounds) ?? cell.drawingRect(forBounds: bounds)
                    precondition(abs(rect.midY - bounds.midY) <= 0.5, "Text must be vertically centered at every width/font")
                    precondition(bounds.contains(rect), "Text must stay inside the input")
                    precondition(rect.height >= ceil(NSLayoutManager().defaultLineHeight(for: font)), "A full text line must fit")
                    checks += 3
                }
            }
        }
        print("Passed \(checks) input geometry and editability checks")
    }
}
