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
        if kind == .latex { return #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"# }
        return #"""
        \begin{tikzpicture}[>=Stealth, scale=1.2]
          \draw[->] (-0.3,0) -- (3.3,0) node[right] {$x$};
          \draw[->] (0,-0.3) -- (0,3.3) node[above] {$y$};
          \draw[blue, thick, domain=0:2.6, samples=50]
            plot (\x,{0.4*\x*\x}) node[right] {$y=0.4x^2$};
        \end{tikzpicture}
        """#
    }
}
