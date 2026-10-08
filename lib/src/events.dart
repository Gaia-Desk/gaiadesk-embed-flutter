import 'dart:convert';

/// Something that happened in a session. Switch exhaustively over the
/// subclasses; kinds this version does not know are dropped.
sealed class EmbedEvent {
  const EmbedEvent();

  /// One event as the library reports it (a JSON string, or the map the
  /// native plugin built from it): `{"type": "code", "code": …}`. Returns null
  /// for a type this version does not know, or for anything malformed.
  static EmbedEvent? parse(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final o = decoded;
    String? s(String k) => o[k] is String ? o[k] as String : null;
    bool b(String k) => o[k] == true;
    switch (o['type']) {
      case 'state':
        final state = s('state');
        return state == null ? null : EmbedState(state);
      case 'code':
        return EmbedCode(
          code: s('code') ?? '',
          sessionId: s('session_id') ?? s('sessionId') ?? '',
          mode: s('mode') ?? 'view',
        );
      case 'joined':
        return EmbedJoined(s('agent'));
      case 'left':
        return const EmbedLeft();
      case 'control':
        return EmbedControl(allowed: b('allowed'));
      case 'action':
        return EmbedAction(action: s('action') ?? '', applied: b('applied'), reason: s('reason'));
      case 'error':
        return EmbedErrorEvent(code: s('code') ?? '', message: s('message') ?? '');
      case 'ended':
        return EmbedEnded(s('reason') ?? '');
      default:
        return null;
    }
  }
}

/// `starting`, `waiting`, `connected`, `ended`.
final class EmbedState extends EmbedEvent {
  const EmbedState(this.state);
  final String state;

  @override
  bool operator ==(Object other) => other is EmbedState && other.state == state;
  @override
  int get hashCode => state.hashCode;
  @override
  String toString() => 'EmbedState($state)';
}

/// The session is registered: [code] is the support code your customer reads
/// to the agent; [mode] is `view` or `cobrowse` (your backend's choice).
final class EmbedCode extends EmbedEvent {
  const EmbedCode({required this.code, required this.sessionId, required this.mode});
  final String code;
  final String sessionId;
  final String mode;

  @override
  bool operator ==(Object other) =>
      other is EmbedCode && other.code == code && other.sessionId == sessionId && other.mode == mode;
  @override
  int get hashCode => Object.hash(code, sessionId, mode);
  @override
  String toString() => 'EmbedCode($code, sessionId: $sessionId, mode: $mode)';
}

/// An agent joined ([agent] is their email, or null).
final class EmbedJoined extends EmbedEvent {
  const EmbedJoined(this.agent);
  final String? agent;

  @override
  bool operator ==(Object other) => other is EmbedJoined && other.agent == agent;
  @override
  int get hashCode => agent.hashCode;
  @override
  String toString() => 'EmbedJoined($agent)';
}

/// The agent left.
final class EmbedLeft extends EmbedEvent {
  const EmbedLeft();

  @override
  bool operator ==(Object other) => other is EmbedLeft;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'EmbedLeft()';
}

/// Guided input paused (`false`) or allowed again (`true`).
final class EmbedControl extends EmbedEvent {
  const EmbedControl({required this.allowed});
  final bool allowed;

  @override
  bool operator ==(Object other) => other is EmbedControl && other.allowed == allowed;
  @override
  int get hashCode => allowed.hashCode;
  @override
  String toString() => 'EmbedControl(allowed: $allowed)';
}

/// An agent's guided request and what became of it. [reason], when not
/// applied: `view_only`, `control_paused`, `rate_limited`, `not_focused`,
/// `outside_app`, `masked`, `embed_ui`, `hint_shown` (iOS), `not_editable`,
/// `unsupported`, …
final class EmbedAction extends EmbedEvent {
  const EmbedAction({required this.action, required this.applied, this.reason});
  final String action;
  final bool applied;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is EmbedAction && other.action == action && other.applied == applied && other.reason == reason;
  @override
  int get hashCode => Object.hash(action, applied, reason);
  @override
  String toString() => 'EmbedAction($action, applied: $applied, reason: $reason)';
}

/// A problem during the session (`capture_failed`, `connect_failed`,
/// `indicator_unavailable`, …). [EmbedEnded] says when the session is over.
final class EmbedErrorEvent extends EmbedEvent {
  const EmbedErrorEvent({required this.code, required this.message});
  final String code;
  final String message;

  @override
  bool operator ==(Object other) => other is EmbedErrorEvent && other.code == code && other.message == message;
  @override
  int get hashCode => Object.hash(code, message);
  @override
  String toString() => 'EmbedErrorEvent($code: $message)';
}

/// The session is over: `stopped` (the customer), `app_stopped`,
/// `disconnected`, `expired` or `error`. Always last, exactly once.
final class EmbedEnded extends EmbedEvent {
  const EmbedEnded(this.reason);
  final String reason;

  @override
  bool operator ==(Object other) => other is EmbedEnded && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
  @override
  String toString() => 'EmbedEnded($reason)';
}
