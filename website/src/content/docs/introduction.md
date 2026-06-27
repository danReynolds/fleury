---
title: Introduction
description: What Fleury is, who it's for, and the mental model in two minutes.
---

Fleury is a **retained-mode UI framework for the terminal** — and, it turns out,
the browser.

The fastest-growing terminal programs aren't utilities anymore; they're
*applications* — agent consoles, dev-tool dashboards, LLM chat surfaces, deploy
monitors — with the screen complexity, input handling, and update rates the word
implies. Many TUI toolkits still fit utility-style screens best. Fleury is built
for application-scale terminal UIs: incremental rendering, real input and focus
management, a widget set deep enough to skip the hand-rolling, and
untrusted-output handling as first-class framework concerns.

## The mental model

If you've written Flutter, you already have it. An immutable **widget** tree
describes the UI, a durable **element** tree holds identity and state (your
`setState` lives there), and a **render** tree lays out and paints — except
Fleury paints to a grid of character **cells**, not pixels. A fourth
**semantics** tree rides alongside, exposing roles and actions for tests and
agents.

The framework itself never mentions a terminal: it paints into an abstract cell
grid, and a **target** turns that grid into something real — diffed ANSI, a
browser DOM, or a streamed session. The
[architecture overview](/architecture/overview/) walks the whole pipeline.

## Where to start

- **New here?** [Getting started](/getting-started/) builds your first app in a
  few minutes.
- **Coming from Flutter?** [The map](/coming-from-flutter/) — what's identical,
  what's renamed, and what's deliberately different.
- **Putting Fleury on the web?**
  [Serving and embedding](/architecture/serving-and-embedding/).
