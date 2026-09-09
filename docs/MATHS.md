# LaTeX and TikZ

Use **File → Insert LaTeX…** for equations or **File → Insert TikZ…** for diagrams. The source editor starts with a working example. Press **Render** when ready.

The result becomes an editable board item: select and move it, drag its bottom-right handle to resize, annotate over it, duplicate it, or save it to the shelf. With the Select tool, double-click an equation or diagram to edit its source. **File → Edit selected equation / diagram…** does the same thing.

## What is retained

Each item stores its original source, a bounded PNG preview, and a PDF asset. Opening a board uses the saved preview; it does not run TeX. Board PNG/PDF export uses the PDF asset, so equations and TikZ paths are redrawn at export resolution. PDF export retains their vector drawing. Saving a board copy includes both assets.

Editing and rendering a duplicated item creates new assets; the original item stays unchanged. An invalid render leaves the existing item in place. The latest attempted source is kept as an in-memory draft for the insert editor. When an edited diagram changes aspect ratio, existing attached ink is adjusted to the new frame; check whether its meaning still matches the changed diagram.

## Examples

LaTeX accepts a maths fragment; surrounding `$…$`, `$$…$$`, `\(…\)` or `\[…\]` delimiters are optional.

```latex
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
```

```latex
\begin{aligned}
f(x) &= x^2 \\
f'(x) &= 2x \\
f'(2) &= 4
\end{aligned}
```

TikZ accepts a `tikzpicture` or its inner drawing commands.

```latex
\begin{tikzpicture}[>=Stealth]
  \node[draw,rounded corners] (a) {Capture};
  \node[draw,rounded corners,right=of a] (b) {Think};
  \node[draw,rounded corners,right=of b] (c) {Keep};
  \draw[->] (a) -- (b);
  \draw[->] (b) -- (c);
\end{tikzpicture}
```

The wrapper provides `amsmath`, `amssymb`, and, for TikZ, `arrows.meta`, `calc`, `positioning`, `shapes.geometric` and `decorations.pathreplacing`. This is an editor for individual equations and diagrams, not a full LaTeX document editor. Handwritten equation recognition is a separate planned feature.

## Local rendering and cost

Creating or editing a render requires local `pdflatex` with the `standalone`, `amsmath`, `amssymb` and `tikz` packages. MacTeX's standard `/Library/TeX/texbin/pdflatex` location is detected; `/opt/homebrew/bin/pdflatex` and `/usr/local/bin/pdflatex` are also checked. No TeX distribution is bundled or automatically downloaded. Saved boards remain viewable without TeX.

Only one render runs at a time, on a utility queue separate from saving and drawing. The child exits after rendering. Source is limited to 64 KB; the preview is capped at 8 million pixels and a 4096-pixel long edge. Compilation has CPU, output-file and wall-time limits. There is no live recompilation on each keystroke and no resident TeX service.

The compiler disables shell escape, restricts file access to its temporary working directory and installed runtime resources, and denies network access. The current macOS isolation mechanism uses `sandbox-exec`; if it cannot start, rendering fails rather than retrying without isolation. Custom user-tree packages, external image files, externalisation and shell-based packages are not supported in this preview.

## Sources and verification

TikZ's official [format guide](https://tikz.dev/drivers) documents loading it through LaTeX; its [installation guide](https://tikz.dev/installation) describes the package requirements. The [standalone manual](https://tug.ctan.org/macros/latex/contrib/standalone/standalone.pdf) documents cropping output to its contents. TeX Live's [2026 changes](https://www.tug.org/texlive/bugs.html) explain why `openin_any` cannot be relied on for input isolation in newer distributions.

Local integration checks rendered a quadratic-formula equation and a TikZ arrow, copied and reopened the equation with source and vector asset intact, rejected invalid TeX and rejected an attempt to read a temporary fixture outside the permitted working directory. These checks supplement the general board tests; they do not establish compatibility with every TeX installation or package.
