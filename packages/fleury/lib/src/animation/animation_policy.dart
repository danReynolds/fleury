// AnimationPolicy: global lever for running or disabling animation,
// used by tests and non-interactive sessions where motion is unwanted.
//
// Lives on TuiBinding. Tickers and animation controllers consult
// the binding's current policy before scheduling work.

/// Whether the animation system should run.
///
/// - [enabled] (default): all animations run at their full
///   configured duration.
/// - [disabled]: nonessential animations snap to their end state
///   synchronously. Repeating decorative animations don't run.
///   Use in CI, non-interactive terminals, or when the user has
///   disabled animation entirely.
///
/// Enforcement lives in `Animation` (disabled → snap to target) and in
/// `Ticker.muted` (propagated from TickerMode + this policy), which gates the
/// discrete-lane widgets (Spinner / BlinkingCursor / FrameBuilder).
enum AnimationPolicy { enabled, disabled }
