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
        if kind == .latex {
            return #"""
\begin{aligned}
f(x)&=x^2-4x+3,\\
f(x)&=(x-1)(x-3)
\end{aligned}
"""#
        }
        return #"""
\begin{tikzpicture}[>=Stealth]
\draw[->] (-0.2,0)--(4.4,0) node[right] {$x$};
\draw[->] (0,-0.2)--(0,3.2) node[above] {$y$};
\draw[blue,very thick] (0.4,0.7) -- (2,2.5) -- (3.7,0.8);
\fill[blue] (2,2.5) circle (2pt) node[above] {idea};
\end{tikzpicture}
"""#
    }
}
