// AnimationPolicy: global lever for shortening, skipping, or
// disabling animation, used by accessibility / CI / SSH / non-
// interactive sessions where animation is unwanted.
//
// Lives on TuiBinding. Tickers and animation controllers consult
// the binding's current policy before scheduling work.

/// How aggressively the animation system should run.
///
/// - [enabled] (default): all animations run at their full
///   configured duration.
/// - [reduced]: decorative transitions are shortened or skipped.
///   Functional animated affordances (cursor blink, spinner
///   indicating in-flight work) continue. Use when the user has
///   opted into reduced animation (accessibility settings, slow
///   terminal, SSH connection with high latency).
/// - [disabled]: nonessential animations snap to their end state
///   synchronously. Repeating decorative animations don't run.
///   Use in CI, non-interactive terminals, or when the user has
///   explicitly opted out of animation entirely.
///
/// Enforcement lives in `Animation` (disabled → snap to target,
/// reduced → shortened) and in `Ticker.muted` (propagated from
/// TickerMode + this policy), which gates the discrete-lane widgets
/// (Spinner / BlinkingCursor / FrameBuilder).
enum AnimationPolicy { enabled, reduced, disabled }
