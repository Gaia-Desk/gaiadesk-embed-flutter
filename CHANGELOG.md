# Changelog

## 0.1.0

- `GaiaDeskEmbed`: share your Flutter app's own screen with your support team from a "Get help"
  button on iOS and Android — consent enforced by the native library, its "Sharing with … · Stop"
  indicator, masked regions painted out before encoding, view-only by default with an opt-in
  guided mode (full on Android, partial on iOS; on iOS a guided click in a Flutter app is always a
  "Tap here" hint, `hint_shown`).
- Consent is an `EmbedConsent` recorded by the native library: `requestConsent` returns
  `EmbedConsent?`, `recordConsent` records the YES of your own dialog, and
  `start(options, consent:)` takes it once, refusing one for another company, capture, or a
  guided session when the user was not asked about guiding (`consent_required`).
- A pause the customer made on the indicator can only be lifted by them (`setPaused(false)` is
  ignored meanwhile).
- `GaiaDeskMasked`: a widget that keeps its rect masked in the running session; a moving widget's
  mask covers where it was, is and is heading, and shrinks back once it stops. On Android, masks
  are refused (`no_activity`) without a foreground activity and Flutter view.
- Obscured text fields (`obscureText: true`) are masked automatically, found in the render tree
  each frame; a focused obscured field stays masked (clamped into the view) even when scrolled
  away. Focus entering or leaving an obscured field is told to the native SDKs
  (`setSecretFocus`), which refuse guided typing and keys there (`masked`).
- `example/`: "Acme Bank", with an obscured PIN field.
