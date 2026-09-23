# Guide demos

Use `FleuryExample` for live exploration by default. Give it one short invitation
and a visible response. Keep the relevant state, handler, and result together in
the source; full source can sit alongside. Tests belong in the repository unless
testing is what the guide teaches.

Open a guide by explaining the problem and the framework's approach. Each section
should introduce a decision or concept, use the example to demonstrate it, and
explain why the result follows. The reader should be able to apply the idea in
another app. Describing what lights up or telling the reader where to click is
an invitation to try a demo, not the lesson itself; keep that in its caption.

Assume readers know UI and programming fundamentals. Spend prose on Fleury's
contracts, implementation choices, and pitfalls, rather than defining buttons,
focus, callbacks, or other familiar concepts. Link to the relevant guide when a
topic already has one. Cut sentences that only restate the example's purpose
or describe behavior the code and demo already make obvious.

Explain behavior in prose; reserve inline code for exact API names or values the
reader needs to identify. Link to reference pages for lists of options instead
of turning the explanation into an API inventory.

Use guided tasks selectively when a reader could miss a behavior, an ordered
sequence helps reveal it, and the demo can reliably detect the result. Keep the
sequence short and optional. Accept equivalent input methods when they teach the
same outcome; never gate the rest of the guide on completion. An obvious button
or slider response does not need a checklist.

The input guide's `InputPractice` is one such exercise: open a note, then cancel a
second press while preserving the open preview. Add another guided exercise only
when it has a similarly concrete learning purpose, not for consistency of chrome.
