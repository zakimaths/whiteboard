# LaTeX and TikZ

Use **File → Insert LaTeX…** for equations or **File → Insert TikZ…** for diagrams. The source editor starts with a working example. Press **Render** when ready.

The result becomes an editable board item: select and move it, drag its bottom-right handle to resize, annotate over it, duplicate it, or save it to the shelf. With the Select tool, double-click an equation or diagram to edit its source. **File → Edit selected equation / diagram…** does the same thing.

## What is retained

Each item stores its original source, a bounded PNG preview, and a PDF asset. Opening a board uses the saved preview; it does not run TeX. Board PNG/PDF export uses the PDF asset, so equations and TikZ paths are redrawn at export resolution. PDF export retains their vector drawing. Saving a board copy includes both assets.

Editing and rendering a duplicated item creates new assets; the original item stays unchanged. An invalid render leaves the existing item in place. The latest attempted source is kept as an in-memory draft for the insert editor. When an edited diagram changes aspect ratio, existing attached ink is adjusted to the new frame; check whether its meaning still matches the changed diagram.

## Examples

LaTeX accepts a maths fragment; surrounding `$…$`, `$$…$$`, `\(…\)` or `\[…\]` delimiters are optional.

The app starts with a simple editable equation and a generic TikZ sketch. More detailed PDEs are available only in the GitHub demo materials. For example, the heat-diffusion initial-boundary value problem is:

```latex
\begin{aligned}
\partial_t u &= \kappa\,\partial_{xx}u,
&&0<x<L,\quad t>0,\\[4pt]
u(0,t)&=u(L,t)=0, &&\kappa>0,\\[4pt]
u(x,0)&=U_0\!\left[\sin\!\frac{\pi x}{L}
       +0.35\sin\!\frac{3\pi x}{L}\right],\\[7pt]
\xi&=x/L,\qquad \tau=\kappa t/L^2,
&&v=u/U_0,\\
v_\tau&=v_{\xi\xi}, &&0<\xi<1.
\end{aligned}
```

The GitHub heat diagram plots its exact modal solution at three dimensionless times. [Editable TikZ source](../Sources/WhiteboardCore/Resources/PDE/heat-diagram.tex). TikZ accepts a `tikzpicture` or its inner drawing commands.

The optional six-board GitHub download includes three PDE models: heat diffusion, wave motion and a Poisson field. Every model includes conditions, a closed-form solution, a labelled diagram and a numerical scheme. The in-app Demo contains only three everyday examples. [Full models, figures, source and checks](PDE-MODELS.md).

The wrapper provides `amsmath`, `amssymb`, and, for TikZ, `arrows.meta`, `calc`, `positioning`, `shapes.geometric` and `decorations.pathreplacing`. This is an editor for individual equations and diagrams, not a full LaTeX document editor. Handwritten equation recognition is a separate planned feature.

## Local rendering and cost

Creating or editing a render requires local `pdflatex` with the `standalone`, `amsmath`, `amssymb` and `tikz` packages. MacTeX's standard `/Library/TeX/texbin/pdflatex` location is detected; `/opt/homebrew/bin/pdflatex` and `/usr/local/bin/pdflatex` are also checked. No TeX distribution is bundled or automatically downloaded. Saved boards remain viewable without TeX.

Only one render runs at a time, on a utility queue separate from saving and drawing. Board editing pauses during compilation so its result cannot race with deletion or undo. The child exits after rendering. Source is limited to 64 KB; the preview is capped at 8 million pixels and a 4096-pixel long edge. Compilation has CPU, output-file and wall-time limits. There is no live recompilation on each keystroke and no resident TeX service.

The compiler disables shell escape, restricts file access to its temporary working directory and installed runtime resources, and denies network access. The current macOS isolation mechanism uses `sandbox-exec`; if it cannot start, rendering fails rather than retrying without isolation. Custom user-tree packages, external image files, externalisation and shell-based packages are not supported in this preview.

## Sources and verification

TikZ's official [format guide](https://tikz.dev/drivers) documents loading it through LaTeX; its [installation guide](https://tikz.dev/installation) describes the package requirements. The [standalone manual](https://tug.ctan.org/macros/latex/contrib/standalone/standalone.pdf) documents cropping output to its contents. TeX Live's [2026 changes](https://www.tug.org/texlive/bugs.html) explain why `openin_any` cannot be relied on for input isolation in newer distributions.

Local integration checks rendered the heat-equation model and Poisson-field TikZ diagram, copied and reopened the equation with source and vector asset intact, rejected invalid TeX and rejected an attempt to read a temporary fixture outside the permitted working directory. These checks supplement the general board tests; they do not establish compatibility with every TeX installation or package.
