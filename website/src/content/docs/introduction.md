---
title: Introduction
description: What Fleury is, who it's for, and the mental model in two minutes.
---

Fleury is a **retained-mode UI framework for the terminal** — and, it turns
out, the browser. If you know Flutter, you already know Fleury's shape:
immutable **widgets** describe the UI, a durable **element** tree holds identity
and state, a **render** tree lays out and paints over a grid of cells, and a
**semantics** tree exposes roles/state/actions for tests and agents.

## Who it's for

The fastest-growing terminal programs aren't utilities — they're *applications*:
agent consoles, dev-tool dashboards, LLM chat surfaces, deploy monitors. They
have the screen complexity, input handling, and update rates that the word
"application" implies. Fleury is built for exactly that: incremental rendering,
real input and focus management, and untrusted-output handling as first-class
framework concerns.

## The mental model

A state change flows through one pipeline:

```
rebuild dirty subtree → layout → paint into a damage-tracked CellBuffer → target
```

The framework never mentions a terminal. It paints into an abstract **cell
grid**; a **target** turns that grid into something real — diffed ANSI for a
terminal, retained DOM for a browser. That separation is what lets one app
definition run as a terminal program, a client-side web bundle, or a remotely
streamed session.

- New to the framework? Start with [Getting started](/getting-started/).
- Want the architecture? See [Core and targets](/architecture/core-and-targets/).
- Putting Fleury on the web? See
  [Serving and embedding](/architecture/serving-and-embedding/).
