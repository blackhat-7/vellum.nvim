---
title: Sample
---

# Vellum *preview* `demo`

A paragraph with **bold**, _italic_, ~~strike~~, `code`, a [link](https://x.y) and https://github.com/x/y. Escaped \*star\* and &amp; entity &#x2192; arrow.
Line two of the same paragraph.  
Hard break above.

## Lists

- one
  continued line
  - nested **two**
    - deeper
- [x] done task
- [ ] open task

3. three
4. four

> [!NOTE]
> Useful information with `code`.

> [!WARNING]
> Careful.

> Plain quote
> > nested quote

| Left | Center | Right |
|:-----|:------:|------:|
| a | **b** | 1 |
| long cell text here | c | 22 |

```lua
local x = { 1, 2 } -- comment
print("hi")
```

```mermaid
flowchart LR
  A[Edit] --> B[Preview]
```

    indented code

---

<!-- hidden comment -->
<p align="center">centered html</p>

<details>
<summary>Click to <b>expand</b></summary>

Hidden on GitHub until clicked, with *markdown* inside.

</details>

## Images

![gradient](images/grad.jpg)

![logo](images/logo.svg)

Badges sit in the text: [![vellum](https://img.shields.io/badge/vellum-nvim-blue.svg)](#) [![license](https://img.shields.io/badge/license-MIT-green.svg)](#) and a big image breaks out: ![logo](images/logo.svg) back to text.

<p align="center"><img src="https://img.shields.io/badge/html-badge-orange.svg" alt="html badge"> <img src="images/dot.gif" alt="dot"></p>

## Math

Inline $E = mc^2$, $\alpha \in \mathbb{R}$ and $`\sqrt{2}`$; it costs $5 and $10.

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

```math
\begin{pmatrix} a & b \\ c & d \end{pmatrix} \quad \sum_{i=1}^n i = \frac{n(n+1)}{2}
```

### Level 3
#### Level 4
##### Level 5
###### Level 6
