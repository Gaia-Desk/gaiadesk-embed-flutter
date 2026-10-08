// The iOS side of gaiadesk_embed: the method channel `gaiadesk_embed` and the
// event channel `gaiadesk_embed/events` over the GaiaDeskEmbed pod.
//
// The SDK owns everything that matters (consent recorded and checked by the
// library, the "Sharing with …"
// indicator, capturing only this app, masking before encoding, guided input).
// This class only converts. Dart's logical pixels are UIKit points, and the
// Flutter view fills the key window, so mask rects pass through unchanged.

import Flutter
import GaiaDeskEmbed
import UIKit

/// A refusal made here, before the SDK is asked (GaiaDeskEmbedError has no
/// public initializer).
struct PluginError: Error {
    let code: String
    let message: String
}

public final class GaiaDeskEmbedPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    /// Events sent while Dart was not listening (bounded).
    private var pending: [[String: Any]] = []
    private var sessions: [Int: GaiaDeskEmbed] = [:]
    private var nextId = 1
    /// Consents the library recorded, by the handle Dart holds (the token
    /// itself never crosses the channel). Single use: `start` takes one out.
    private var consents: [String: GaiaDeskEmbed.Consent] = [:]
    private var nextConsent = 1

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = GaiaDeskEmbedPlugin()
        let methods = FlutterMethodChannel(name: "gaiadesk_embed", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(name: "gaiadesk_embed/events", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        pending.forEach { events($0) }
        pending.removeAll()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    // MARK: - Methods (Flutter calls these on the main thread)

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let session = (args["session"] as? NSNumber)?.intValue
        do {
            switch call.method {
            case "start":
                result(try MainActor.assumeIsolated { try start(args) })
            case "stop":
                if let session { sessions[session]?.stop() }
                result(nil)
            case "setMaskedRects":
                if let session { try sessions[session]?.setMaskedRects(Self.rects(args["masks"])) }
                result(nil)
            case "setPaused":
                if let session { sessions[session]?.setPaused(args["paused"] as? Bool ?? false) }
                result(nil)
            case "requestConsent":
                let company = args["company"] as? String ?? ""
                let guided = args["guided"] as? Bool ?? false
                Task { @MainActor in
                    let consent = await GaiaDeskEmbed.requestConsent(company: company, guided: guided)
                    result(consent.map { self.keep($0) })
                }
            case "recordConsent":
                if args["capture"] as? String == "screen" {
                    throw PluginError(code: "bad_config", message: "capture: screen is Android only; iOS shares the app alone")
                }
                let consent = try GaiaDeskEmbed.recordConsent(company: args["company"] as? String ?? "", guided: args["guided"] as? Bool ?? false)
                result(keep(consent))
            case "buildInfo":
                result(GaiaDeskEmbed.buildInfo)
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let e as GaiaDeskEmbedError {
            result(FlutterError(code: e.code, message: e.message, details: nil))
        } catch let e as PluginError {
            result(FlutterError(code: e.code, message: e.message, details: nil))
        } catch {
            result(FlutterError(code: "unknown", message: "\(error)", details: nil))
        }
    }

    private func keep(_ consent: GaiaDeskEmbed.Consent) -> String {
        let ref = "c\(nextConsent)"
        nextConsent += 1
        consents[ref] = consent
        return ref
    }

    @MainActor
    private func start(_ args: [String: Any]) throws -> Int {
        if args["capture"] as? String == "screen" {
            throw PluginError(code: "bad_config", message: "capture: screen is Android only; iOS shares the app alone")
        }
        var server: URL?
        if let s = args["server"] as? String {
            guard let u = URL(string: s) else {
                throw PluginError(code: "bad_server", message: "server must be an http(s) URL (got \"\(s)\")")
            }
            server = u
        }
        let config = GaiaDeskEmbed.Configuration(
            embedToken: args["embedToken"] as? String ?? "",
            company: args["company"] as? String ?? "",
            server: server,
            guided: args["guided"] as? Bool ?? false,
            fps: (args["fps"] as? NSNumber)?.intValue ?? 15,
            maskedRects: Self.rects(args["masks"]),
            captureMethod: args["captureMethod"] as? String == "snapshot" ? .snapshot : .replayKit
        )
        let id = nextId
        nextId += 1
        guard let ref = args["consent"] as? String, let consent = consents.removeValue(forKey: ref) else {
            throw PluginError(code: "consent_required", message: "ask your user first (requestConsent, or recordConsent after your own dialog); a consent starts one session")
        }
        let embed = try GaiaDeskEmbed.start(config, consent: consent) { [weak self] event in
            guard let self else { return }
            if case .ended = event { self.sessions.removeValue(forKey: id) }
            self.send(id, Self.map(event))
        }
        sessions[id] = embed
        return id
    }

    private func send(_ id: Int, _ event: [String: Any]) {
        let msg: [String: Any] = ["session": id, "event": event]
        if let sink {
            sink(msg)
        } else if pending.count < 256 {
            pending.append(msg)
        }
    }

    /// `[{x, y, w, h}]` in logical pixels == window points.
    static func rects(_ raw: Any?) -> [CGRect] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.map { r in
            let n = { (k: String) in (r[k] as? NSNumber)?.doubleValue ?? 0 }
            return CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h"))
        }
    }

    /// One SDK event as the library's JSON shape.
    static func map(_ e: GaiaDeskEmbed.Event) -> [String: Any] {
        switch e {
        case let .state(s):
            return ["type": "state", "state": s]
        case let .code(code, sessionId, mode):
            return ["type": "code", "code": code, "session_id": sessionId, "mode": mode]
        case let .joined(agent):
            return ["type": "joined", "agent": agent ?? NSNull()]
        case .left:
            return ["type": "left"]
        case let .control(allowed):
            return ["type": "control", "allowed": allowed]
        case let .action(action, applied, reason):
            return ["type": "action", "action": action, "applied": applied, "reason": reason ?? NSNull()]
        case let .error(code, message):
            return ["type": "error", "code": code, "message": message]
        case let .ended(reason):
            return ["type": "ended", "reason": reason]
        }
    }
}
