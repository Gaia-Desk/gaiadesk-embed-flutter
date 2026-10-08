/// GaiaDesk embed for Flutter: a "Get help" button that shares your app's own
/// screen with your support team, consent first, with an always-visible
/// "Sharing with `<company>` · Stop" indicator, masked regions painted out
/// before encoding, and view-only by default.
///
/// A Dart layer over GaiaDesk's mobile embed SDKs (`GaiaDeskEmbed` on iOS,
/// `net.gaiadesk:embed-android` on Android). The native library is the real
/// gate: it refuses to start without consent and owns the indicator.
library;

export 'src/embed.dart' show GaiaDeskEmbed, EmbedBuildInfo, EmbedConsent;
export 'src/events.dart';
export 'src/exception.dart';
export 'src/masked.dart' show GaiaDeskMasked;
export 'src/options.dart';
export 'src/session.dart' show EmbedSession;
