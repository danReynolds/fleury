---
title: Introduction
description: What Fleury is, who it's for, and the mental model in two minutes.
---

Fleury is a **Dart UI framework for the terminal** — and, it turns out, the
browser. You describe the UI as a tree of widgets, and the framework keeps that
tree between frames and updates only what changed.

Many new terminal programs aren't utilities; they're *applications* — agent
consoles, dev-tool dashboards, LLM chat surfaces, deploy monitors — with the screen complexity, input handling, and update rates the word
implies. Many TUI toolkits still fit utility-style screens best. Fleury is built
for application-scale terminal UIs: incremental rendering, real input and focus
management, a widget set deep enough to skip the hand-rolling, and safe display
of untrusted text, such as model output and logs, as first-class framework
concerns.

## The mental model

If you've written Flutter, you already have it. An immutable **widget** tree
describes the UI, a durable **element** tree holds identity and state (your
`setState` lives there), and a **render** tree lays out and paints — except
Fleury paints to a grid of character **cells**, not pixels. A fourth
**semantics** tree rides alongside, exposing roles and actions for tests and
agents.

The framework itself never writes to a terminal: it paints into an abstract cell
grid, and a **target** turns that grid into something real — diffed ANSI, a
browser DOM, or a streamed session. The
[architecture overview](/fleury/architecture/overview/) walks the whole pipeline.

## Where to start

- **Want to experiment in your browser?** [Fleury Pad](/fleury/pad/) pairs a Dart
  editor with a running app and stateful hot reload.
- **New here?** [Getting started](/fleury/getting-started/) builds your first app in a
  few minutes, and the [tutorial](/fleury/tutorial/) walks through a complete small
  app.
- **Building something?** The [guides](/fleury/guides/) cover one task each, and the
  [widget reference](/fleury/widgets/) has a live demo for most widgets.
- **Still deciding?** [Why Fleury](/fleury/comparison/) — what it does that peers
  don't, and when to pick something else.
- **Coming from Flutter?** [The map](/fleury/coming-from-flutter/) — what's identical,
  what's renamed, and what's deliberately different.
- **Putting Fleury on the web?**
  [Serving and embedding](/fleury/architecture/serving-and-embedding/).
