# Worked PDE models

The optional academic sample pack uses detailed partial differential equations, with typeset mathematics and original TikZ diagrams. GitHub provides rendered PNG/PDF assets, editable Whiteboard files and their source. The app's built-in Demo remains a small general-purpose workspace; it does not add PDE boards to a personal or demo library. Editing and rendering TeX source still needs local TeX.

| Model | Conditions and solution | Diagram and numerical method |
| --- | --- | --- |
| Heat diffusion | Uniform rod; zero Dirichlet ends; first and third sine modes in the initial data; exact exponential modal decay and the L2 energy identity | Three exact profiles at dimensionless times 0, 0.04 and 0.12; forward-Euler centred-space scheme and its stability restriction |
| Fixed string | Undamped wave equation; fixed ends; first-mode displacement and zero initial velocity; standing-wave solution and conserved energy | Signed displacement profiles at four phases; centred time/space update, special first step and CFL restriction |
| Poisson field | Unit square; zero Dirichlet boundary; a manufactured sine-product solution; strong and weak forms, maximum and energy check | Exact field sampled on a 24 × 24 display grid, labelled colour scale and five-point stencil; linear system and residual |

These are worked mathematical examples, not an interactive PDE solver. Curves come from the stated closed-form solutions. The Poisson field shows cell-centre samples of the exact solution, not output from solving a finite-difference system. Colours and line styles distinguish the time profiles; diagram labels use dimensionless coordinates where appropriate.

## Heat diffusion

Assume length L > 0, constant diffusivity κ > 0 and amplitude U₀ > 0. The field is temperature relative to the fixed endpoint temperature. Diffusivity has units of length squared per time. With ξ = x/L and τ = κt/L², both plotted coordinates are dimensionless. The plotted third-mode coefficient is 0.35; its decay rate is nine times the first mode's. E is an L2 energy functional, not the total thermodynamic heat content.

![Heat equation, conditions, exact solution, energy check and numerical scheme](demos/pde-heat.png)

[Vector PDF](demos/pde-heat.pdf) · [Equation source](../Sources/WhiteboardCore/Resources/PDE/heat-model.tex) · [TikZ source](../Sources/WhiteboardCore/Resources/PDE/heat-diagram.tex)

**Readable equation companion.** The temperature satisfies “the time derivative of u equals κ times the second x derivative of u” on a rod from 0 to L. Both endpoint values are zero. The initial temperature is U₀ times the sum of the first sine mode and 0.35 times the third sine mode. At dimensionless time τ, their amplitudes are multiplied by exp(−π²τ) and exp(−9π²τ). The derivative of one half the integral of u squared is minus κ times the integral of the squared spatial derivative, so this L2 energy cannot increase. The explicit grid update applies at interior indices j = 1 through N − 1 and is stable for positive r = κΔt/Δx² no greater than one half.

**Diagram description.** A horizontal dimensionless rod coordinate runs from zero to one. The initial blue curve has two symmetric peaks because it combines the first and third modes. At τ = 0.04 the dashed teal curve is smoother and lower; at τ = 0.12 the dotted amber curve is lower again and resembles the first sine mode. Every curve is zero at both endpoints.

## Wave motion

Assume L, c and A are positive. The model is a uniform, undamped string with small transverse displacement, fixed endpoints and zero initial velocity. Time is plotted as θ = ct/L. The dotted profile is at θ = 1/2, where displacement is zero but velocity is not: energy has not disappeared. The conserved functional is the usual wave energy scaled by the constant mass-density factor.

![Wave equation, fixed endpoints, standing wave and numerical update](demos/pde-wave.png)

[Vector PDF](demos/pde-wave.pdf) · [Equation source](../Sources/WhiteboardCore/Resources/PDE/wave-model.tex) · [TikZ source](../Sources/WhiteboardCore/Resources/PDE/wave-diagram.tex)

**Readable equation companion.** The transverse displacement satisfies “the second time derivative of u equals c squared times the second x derivative of u,” with fixed zero-displacement endpoints. It starts as the first sine mode with zero velocity. The exact motion is A times cosine of πct/L times sine of πx/L, with period 2L/c. One half the integral of velocity squared plus c squared times slope squared is constant. The centred grid update applies at interior indices j = 1 through N − 1 for n at least one and requires the positive Courant number cΔt/Δx to be no greater than one.

**Diagram description.** The string is a positive sine arch at phase θ = 0, a lower positive arch at θ = 1/4, flat at θ = 1/2, and an inverted arch at θ = 1. The endpoints remain fixed. At the flat phase the velocity is largest, so the system's energy is kinetic rather than absent.

## Poisson problem

Coordinates are nondimensionalised on the unit square. The source is chosen to match u = sin(πx) sin(πy), allowing boundary values, residuals and grid refinement to be checked against a known answer. The weak form uses H₀¹ test functions; the five-point matrix refers to interior unknowns with homogeneous Dirichlet boundary values removed. It is symmetric positive definite: zᵀAz is positive for every nonzero vector z. The algebraic residual f − Auₕ measures how accurately a linear system has been solved; it is distinct from truncation error and from the error between uₕ and the exact field. The app itself does not run a solver.

![Poisson equation, weak form, exact field and five-point stencil](demos/pde-poisson.png)

[Vector PDF](demos/pde-poisson.pdf) · [Equation source](../Sources/WhiteboardCore/Resources/PDE/poisson-model.tex) · [TikZ source](../Sources/WhiteboardCore/Resources/PDE/poisson-diagram.tex)

**Readable equation companion.** On the unit square, minus the Laplacian of u equals 2π² times sin(πx) sin(πy), and u is zero on the entire boundary. The exact solution is sin(πx) sin(πy), whose maximum is one at the centre. Its energy integral, the integral of the squared gradient, equals π²/2. At every interior grid point, the five-point approximation is four times the centre value minus its four axial neighbours, all divided by h squared. The maximum-norm solution error decreases quadratically with h for this smooth problem.

**Diagram description.** A square field is zero around its boundary, rises smoothly and symmetrically, and reaches one at the centre. A blue sequential colour scale runs from white at zero to dark teal at one. Beside it, the five-point stencil has weight four at the centre and minus one at each of the left, right, upper and lower neighbours; every weight is divided by h squared.

## Verification and source material

The example data and diagrams are original. The mathematical methods follow standard Fourier separation for diffusion, wave-energy arguments and centred finite differences. Supporting primary teaching material: [MIT Fourier series and the heat equation](https://math.mit.edu/~gs/cse/websections/cse41.pdf), [MIT Waves and Imaging notes](https://math.mit.edu/icg/resources/teaching/18.367/notes367.pdf), and [MIT numerical PDE course materials](https://math.mit.edu/classes/18.336/index.html).

`python3 scripts/check_pde_models.py` independently checks sampled PDE residuals inside the stated time domain, boundary and initial data, the heat and wave energy identities, second-order truncation error, and maximum-norm convergence after actually solving the Poisson grid system. It uses Python's standard library. These are numerical consistency checks of the displayed formulas, not a symbolic proof or a LaTeX parser. All twelve equation/diagram fragments were compiled with the real local TeX engine, and the full board exports were visually inspected.

To regenerate the bundled rendered assets after editing the source files:

```sh
swift run WhiteboardPDEAssets Sources/WhiteboardCore/Resources/PDE
bash scripts/build.sh
```

This developer step needs local TeX and runs only when explicitly requested. To build a fresh downloadable gallery library and its PNG/PDF exports, run `swift run WhiteboardSamples --pde <new-library-folder> <export-folder>`. Without `--pde`, the tool creates only the three general-purpose examples. Opening Demo in the app does not install these PDE boards.

`swift run WhiteboardPDEAssets --check Sources/WhiteboardCore/Resources/PDE` recompiles every fragment and fails if any committed PNG preview has drifted from its editable source. PDF files are regenerated for releases because TeX embeds variable creation metadata; the deterministic PNG comparison checks the visible mathematical content.
