# gaiadesk_embed (Flutter)

A **"Get help" button for your Flutter app** on iOS and Android. Your customer taps it and agrees;
**your app's own screen** is shared with **your** support team, who see it in the GaiaDesk
console's Support page and, if you allow it, guide it.

- Dart API over GaiaDesk's mobile embed SDKs: the `GaiaDeskEmbed` pod on iOS and
  `net.gaiadesk:embed-android` on Android. No other dependencies.
- **Consent first**: the native library refuses to start until your user has agreed. Use the SDK's
  dialog (`requestConsent`) or your own.
- Shares **your app only** (iOS always; Android by default). The whole Android screen is an opt-in.
- A visible **"Sharing with Acme · Stop"** indicator, drawn by the native SDK, for as long as
  anything is shared. Frames only leave while it is on screen.
- **Mask** card numbers, balances, passwords: wrap them in `GaiaDeskMasked` and they are painted
  black before a frame is encoded.
- **View-only by default.** Guided mode delivers the agent's input inside your app, and your
  customer can pause it.
- No install, no service, nothing written to disk: the session ends when your app calls `stop()`,
  the customer presses Stop, or the app quits.

## Install

```yaml
# pubspec.yaml
dependencies:
  gaiadesk_embed: ^0.1.0
```

**iOS** (15.0+): the plugin's pod depends on `GaiaDeskEmbed` (`~> 0.1`), which carries the Swift
SDK and the prebuilt `GaiaDeskEmbedFFI.xcframework`. Set `platform :ios, '15.0'` in
`ios/Podfile`. To build against a local checkout of `gaiadesk-embed-ios` (with its XCFramework
fetched by `scripts/fetch-binary.sh`), add `pod 'GaiaDeskEmbed', :path => '…/gaiadesk-embed-ios'`
to your Runner target (the example's Podfile does this when `GAIADESK_EMBED_IOS_PATH` is set).

**Android** (minSdk 26): the plugin depends on `net.gaiadesk:embed-android:0.1.0` (the Kotlin SDK
and `libgaiadesk_embed.so` for arm64-v8a, armeabi-v7a and x86_64) from Maven Central. Set
`minSdk = 26` in `android/app/build.gradle.kts`. Overrides, in your `android/gradle.properties`
(or as environment variables):

- `GaiaDeskEmbed_embedAndroidMavenLocal=true` (`GAIADESK_EMBED_ANDROID_MAVEN_LOCAL=1`): resolve it
  from `~/.m2` as well, after `./gradlew :embed:publishToMavenLocal` in `gaiadesk-embed-android`
  (the example also lists `mavenLocal()` itself);
- `GaiaDeskEmbed_embedAndroidAar=/path/to/embed-android-0.1.0.aar` (`GAIADESK_EMBED_ANDROID_AAR`):
  that AAR file instead (e.g. the one attached to a gaiadesk-embed-android release);
- `GaiaDeskEmbed_embedAndroidVersion=<version>`: another published version.

## Quick start

Your backend creates a support session with a secret API key (scope `support`) and hands the app
its `embed_token`; the session's `mode` (`view` or `cobrowse`) is your backend's choice:

```sh
curl -s -X POST https://api.gaiadesk.net/v1/support/sessions \
  -H "Authorization: Bearer $GAIADESK_API_KEY" -H "Content-Type: application/json" \
  -d '{"mode": "view", "customer": {"name": "Ada", "plan": "pro"}}'
# → {"id": "ss_…", "join_code": "123456789", "embed_token": "gdemb_…", …}
```

(A mobile app uses a token from its backend, never a key: a key in a shipped app is anyone's.)

```dart
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

Future<void> getHelp(String embedToken) async {
  // 1. Ask.
  final agreed = await GaiaDeskEmbed.requestConsent('Acme');
  if (!agreed) return;

  // 2. Start, with the answer.
  try {
    final help = await GaiaDeskEmbed.start(
      EmbedOptions(embedToken: embedToken, company: 'Acme'),
      consentGranted: agreed,
    );
    help.events.listen((e) {
      switch (e) {
        case EmbedCode(:final code):
          print('support code $code'); // your customer reads it to the agent
        case EmbedJoined(:final agent):
          print('${agent ?? 'an agent'} is viewing');
        default:
          break;
      }
    });
    print('ended: ${await help.ended}');
  } on EmbedException catch (e) {
    print('could not start: ${e.code} ${e.message}'); // bad_token, consent_required, …
  }
}
```

Your support team opens **Support** in the GaiaDesk console, sees the waiting customer and joins
(or types the nine-digit code).

`example/` is a complete app ("Acme Bank"): a masked card, a Buy button, a token field and Get
help.

## Consent is required

`start` refuses (`EmbedException` with code `consent_required`) unless `consentGranted` is
literally `true`, and that must be your user's answer to a consent dialog: `requestConsent` (a
`UIAlertController` on iOS, an `AlertDialog` on Android) or your own. Say who will see what, and
whether they can act. The check in Dart is a convenience; the native library makes it again and is
the real gate.

## Masking

```dart
GaiaDeskMasked(child: CardNumber(card))
```

A `GaiaDeskMasked` widget reports its rect (logical pixels, from the top-left of the Flutter view)
after every frame and keeps the running session's masks current. Widgets on screen when you call
`start` are masked from the very first frame. A mask reaches the native side after the frame that
moved its widget, so while a masked widget moves (scrolling, an animation) its mask is widened to
cover where it was, where it is and where it is heading at its current speed, and shrinks back to
the exact rect once it is still. A widget that jumps (appears, or moves abruptly) can still show for
one frame, so for such content mask the area it moves in, or a larger ancestor: masking too much is
safe, too little is not. On Android, masks need the foreground activity's Flutter view to be placed;
without one, `setMaskedRects` and `start` with masks are refused (`no_activity`) rather than
placed at a guess.

Regions you know yourself go in `EmbedOptions.masks` at start and `session.setMaskedRects(rects)`
afterwards (`Rect`s in logical pixels, e.g. from `RenderBox.localToGlobal`); these replace each
other, and the `GaiaDeskMasked` widgets are always added. The native side converts: on iOS
logical pixels are window points; on Android they are multiplied by the display density and
offset by the Flutter view's position in the window. `setMaskedRects([])` clears your own rects.

## Guided mode

Sessions are **view-only by default**. Guided input needs **both** `guided: true` in your options
**and** a `cobrowse` session (your backend's `mode`). Even then, a request is applied only inside
your app, while it is in front, not on a mask and not on the indicator. Your customer can pause it
on the indicator; you can too, with `session.setPaused(true)`. Every request is reported as an
`EmbedAction` with `applied` and a `reason`.

- **Android: full.** Clicks become taps, scrolling a mouse-wheel scroll, typing key events, all
  dispatched into your activity's own window, so into the Flutter view, which handles them like
  any touch or hardware key (a focused `TextField` receives typing).
- **iOS: hints, not taps.** iOS has no public way to synthesise a touch. The native SDK presses
  UIKit controls directly, but Flutter renders its own widgets into one view, with no UIKit
  control behind a button, so in a Flutter app a guided click **never presses anything**: your
  customer sees a **"Tap here"** ring at that spot and taps it themselves, and the agent gets
  `EmbedAction(applied: false, reason: 'hint_shown')` (the console shows the session as "shown
  where to tap"). Clicks on a masked widget are refused (`masked`), and paused input is refused
  (`control_paused`). Typing goes into the first responder (a focused Flutter `TextField` is
  one). Pointer and highlight are drawn. Plan your support flow on iOS as guiding, not driving.

## The indicator

While anything is shared, the native SDK shows **"Sharing with `<company>`"** with **Stop** (and, in
guided sessions, Pause / Allow control), above your UI. Frames are sent only while it is up. Stop
ends everything; you get `EmbedEnded('stopped')`.

## Capture

- **iOS: your app only, always.** `captureMethod: IosCaptureMethod.replayKit` (default) uses
  ReplayKit's in-app capture: exactly what the app shows, Flutter's Metal output included; iOS asks
  the user to allow recording the first time, and it is unavailable in the Simulator.
  `IosCaptureMethod.snapshot` snapshots the app's windows with no system prompt and works in the
  Simulator. `capture: EmbedCapture.screen` is refused on iOS (`bad_config`).
- **Android: your app's window by default** (`EmbedCapture.app`, PixelCopy: no permission, no
  system dialog). `EmbedCapture.screen` shares the device screen through MediaProjection: Android
  shows its own consent after yours, a foreground service runs while sharing, and your app must
  declare, in `android/app/src/main/AndroidManifest.xml`:

  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
  ```

  Without them, starting fails with `capture_failed`. Pass the same `capture` to `requestConsent`
  so the wording says "screen".

## API

| | |
|---|---|
| `GaiaDeskEmbed.start(options, consentGranted:)` | `Future<EmbedSession>`; throws `EmbedException` (`.code`, `.message`) |
| `GaiaDeskEmbed.requestConsent(company, {guided, capture})` | `Future<bool>`: the user's answer |
| `GaiaDeskEmbed.buildInfo()` | `Future<EmbedBuildInfo>`: `version`, `codec`, `os`, `arch`, `testSource`, `raw` |
| `GaiaDeskEmbed.current` | the running `EmbedSession`, or null |
| `session.events` | `Stream<EmbedEvent>` (broadcast; events before the first listener are kept for it; closes after `EmbedEnded`) |
| `session.ended` | `Future<String>`: the end reason, completes exactly once |
| `session.stop()` | end the session (safe to call again); `EmbedEnded('app_stopped')` follows |
| `session.setMaskedRects(rects)` | replace your own masked rects (logical pixels) |
| `session.setPaused(paused)` | pause or resume guided input |
| `GaiaDeskMasked(child:)` | paint a widget out of everything shared |

| `EmbedOptions` | |
|---|---|
| `embedToken` | `gdemb_…`, from your backend |
| `company` | shown on the consent dialog and the indicator |
| `server` | the GaiaDesk server (default `https://gaiadesk.net`) |
| `guided` | allow guided input (default `false`; see Guided mode) |
| `fps` | 1 to 30 (default 15) |
| `masks` | `List<Rect>` painted out from the first frame (logical pixels) |
| `capture` | Android: `EmbedCapture.app` (default) or `EmbedCapture.screen` (opt-in) |
| `captureMethod` | iOS: `IosCaptureMethod.replayKit` (default) or `IosCaptureMethod.snapshot` |

| Event | |
|---|---|
| `EmbedState(state)` | `starting`, `waiting`, `connected`, `ended` |
| `EmbedCode(code:, sessionId:, mode:)` | registered; `code` is what the agent joins with |
| `EmbedJoined(agent)` / `EmbedLeft()` | an agent (email, or null) joined / left |
| `EmbedControl(allowed:)` | guided input paused or allowed again |
| `EmbedAction(action:, applied:, reason:)` | a guided request and its outcome (`view_only`, `control_paused`, `rate_limited`, `not_focused`, `outside_app`, `masked`, `embed_ui`, `hint_shown`, `not_editable`, `unsupported`) |
| `EmbedErrorEvent(code:, message:)` | e.g. `capture_failed`, `connect_failed`, `indicator_unavailable` |
| `EmbedEnded(reason)` | `stopped` (the customer), `app_stopped`, `disconnected`, `expired`, `error`: always last, exactly once |

`EmbedEvent` is sealed: `switch` over it exhaustively. Events arrive on the main isolate, in order;
kinds this version does not know are dropped. One session at a time (a second `start` while one
runs fails with `busy`). Refusal codes include `consent_required`, `bad_token`, `bad_server`,
`bad_config`, `bad_rects`, `busy`, `no_activity` (Android, no foreground activity) and
`unsupported_platform`.

## Example

```sh
cd example
flutter run --dart-define=GAIADESK_EMBED_TOKEN=gdemb_… \
  [--dart-define=GAIADESK_SERVER=https://…] [--dart-define=GAIADESK_DEMO_AUTOSTART=1]
```

Every event is printed as one line (`flutter logs`). On the iOS Simulator, switch the example to
`IosCaptureMethod.snapshot`. For tests, the example also reads the same `GAIADESK_DEMO_*`
environment variables as the native iOS examples (`example/lib/demo_hooks.dart`; on the Simulator
pass them as `SIMCTL_CHILD_*` to `xcrun simctl launch`): autostart, test-only consent, guided,
snapshot capture, and stop/pause/resume through a command file. GaiaDesk's
`e2e/embed-flutter-ios-sim.mts` drives it against a real server and console.

## Development

```sh
flutter test      # Dart: options, events, sessions, masks (a fake native side)
flutter analyze
```

The channel contract: method channel `gaiadesk_embed` (`start` → a plugin session id, `stop`,
`setMaskedRects`, `setPaused`, `requestConsent`, `buildInfo`) and event channel
`gaiadesk_embed/events` (`{session, event}`, `event` being the library's event JSON, as a map or a
string).

## Releasing (maintainers)

Publish the native SDKs first (the `GaiaDeskEmbed` pod on CocoaPods trunk, `net.gaiadesk:embed-android`
on Maven Central): this plugin only depends on them. Then, with the version bumped in
`pubspec.yaml`, `ios/gaiadesk_embed.podspec`, `android/build.gradle.kts` and `CHANGELOG.md`:

```sh
flutter analyze && flutter test
flutter pub publish --dry-run          # must end with "Package has 0 warnings."
git tag v0.1.0 && git push origin main v0.1.0
flutter pub publish                    # a pub.dev account (Google sign-in) that is an uploader;
                                       # the first upload creates the package
```

## Licences

- This package's Dart, Swift and Kotlin sources and the example: **MIT** (`LICENSE`).
- The native GaiaDesk embed library the platform SDKs bundle (`GaiaDeskEmbedFFI.xcframework`,
  `libgaiadesk_embed.so`): closed source, under the **GaiaDesk Native Binary Licence**
  (`LICENSE-BINARY`): free to use in your apps, inside them, unmodified.
