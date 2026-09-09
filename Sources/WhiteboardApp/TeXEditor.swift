import AppKit
import WhiteboardCore

enum TeXEditor {
    static func edit(kind: TeXKind, initial: String?) -> TeXSource? {
        let alert = NSAlert()
        alert.messageText = kind == .latex ? "LaTeX equation" : "TikZ diagram"
        alert.informativeText = kind == .latex ? "Enter maths, including fractions, matrices or aligned equations. Render when ready; you can edit the source later." : "Enter a tikzpicture or drawing commands. Render when ready; you can edit the source later."
        alert.addButton(withTitle:"Render"); alert.addButton(withTitle:"Cancel")
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:620,height:300))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let editor = NSTextView(frame:scroll.bounds)
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize:14,weight:.regular)
        editor.textContainerInset = NSSize(width:12,height:12)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.string = initial ?? sample(kind)
        editor.setAccessibilityLabel(kind == .latex ? "LaTeX source" : "TikZ source")
        scroll.documentView = editor; alert.accessoryView = scroll; alert.window.initialFirstResponder = editor
        return alert.runModal() == .alertFirstButtonReturn ? TeXSource(kind:kind,code:editor.string) : nil
    }
    static func sample(_ kind: TeXKind) -> String {
        return (try? PDEExamples.source(kind == .latex ? "heat-model" : "heat-diagram",kind:kind).code) ?? #"u_t=\kappa u_{xx}"#
    }
}
