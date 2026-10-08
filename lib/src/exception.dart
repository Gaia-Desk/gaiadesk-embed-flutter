import 'package:flutter/services.dart';

/// A refusal: [code] is stable (`consent_required`, `bad_token`, `bad_config`,
/// `bad_rects`, `busy`, `no_activity`, `unsupported_platform`, …), [message]
/// is for people.
class EmbedException implements Exception {
  const EmbedException(this.code, this.message);

  /// A refusal the native layer reported through the method channel.
  factory EmbedException.fromPlatform(PlatformException e) =>
      EmbedException(e.code, e.message ?? '');

  final String code;
  final String message;

  @override
  String toString() => 'EmbedException($code): $message';

  @override
  bool operator ==(Object other) =>
      other is EmbedException && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}
