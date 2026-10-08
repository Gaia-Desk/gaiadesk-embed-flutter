# Changelog

## Unreleased

- Obscured text fields (`obscureText: true`) are masked automatically, found in the render tree
  each frame; a focused obscured field stays masked (clamped into the view) even when scrolled
  away, so guided typing into it is refused (`masked`).
- **Breaking:** consent is an `EmbedConsent` recorded by the native library, not a bool.
  `requestConsent` returns `EmbedConsent?`; `recordConsent` records the YES of your own dialog;
  `start(options, consent:)` takes it once, and refuses one for another company, capture, or a
  guided session when the user was not asked about guiding (`consent_required`).
- A pause the customer made on the indicator can only be lifted by them (`setPaused(false)` is
  ignored meanwhile).
- iOS: the plugin compiles against GaiaDeskEmbed (its own refusals no longer use the SDK error's
  initializer).
- `GaiaDeskMasked`: a moving widget's mask is widened to where it was, is and is heading (one
  frame at its speed) and shrinks back once it stops, instead of trailing it by a frame.
- Android: masks are refused (`no_activity`) without a foreground activity and Flutter view,
  instead of being placed with density 1 at offset 0.
- README: on iOS a guided click in a Flutter app is always a "Tap here" hint (`hint_shown`).

## 0.1.0

- `GaiaDeskEmbed`: share your Flutter app's own screen with your support team from a "Get help"
  button on iOS and Android — consent enforced by the native library, its "Sharing with … · Stop"
  indicator, masked regions painted out before encoding, view-only by default with an opt-in
  guided mode (full on Android, partial on iOS).
- `GaiaDeskMasked`: a widget that keeps its rect masked in the running session.
- `example/`: "Acme Bank".
