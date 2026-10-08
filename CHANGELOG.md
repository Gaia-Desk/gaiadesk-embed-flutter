# Changelog

## Unreleased

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
