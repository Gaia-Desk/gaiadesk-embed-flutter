// The Android side of gaiadesk_embed: the method channel `gaiadesk_embed` and
// the event channel `gaiadesk_embed/events` over net.gaiadesk:embed-android.
//
// The SDK owns everything that matters (consent recorded and checked by the
// library, the "Sharing with …"
// indicator, masking before encoding, guided input delivered as touch and key
// events into this activity's window, so into the Flutter view). This class
// only converts: Dart's logical pixels to window pixels, and the SDK's events
// to maps.
package net.gaiadesk.embed.flutter

import android.app.Activity
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.gaiadesk.embed.GaiaDeskEmbed
import net.gaiadesk.embed.GaiaDeskEmbedException

class GaiaDeskEmbedPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var activity: Activity? = null

    /** Events sent while Dart was not listening (bounded). */
    private val pending = ArrayDeque<Map<String, Any?>>()
    private val sessions = HashMap<Int, GaiaDeskEmbed>()
    private var nextId = 1

    /**
     * Consents the library recorded, by the handle Dart holds (the token itself never crosses the
     * channel). Single use: `start` takes one out.
     */
    private val consents = HashMap<String, GaiaDeskEmbed.Consent>()
    private var nextConsent = 1

    private fun keep(consent: GaiaDeskEmbed.Consent): String {
        val ref = "c${nextConsent++}"
        consents[ref] = consent
        return ref
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, "gaiadesk_embed").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "gaiadesk_embed/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAll()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        // The shared activity is going away: nothing is left to share.
        stopAll()
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        while (pending.isNotEmpty()) events.success(pending.removeFirst())
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> start(call, result)
                "stop" -> {
                    sessions[call.argument<Int>("session")]?.stop()
                    result.success(null)
                }
                "setMaskedRects" -> {
                    val s = sessions[call.argument<Int>("session")]
                    s?.setMaskedRects(rects(call.argument<List<Map<String, Number>>>("masks")))
                    result.success(null)
                }
                "setPaused" -> {
                    sessions[call.argument<Int>("session")]?.setPaused(call.argument<Boolean>("paused") == true)
                    result.success(null)
                }
                "requestConsent" -> requestConsent(call, result)
                "recordConsent" -> {
                    val consent = GaiaDeskEmbed.recordConsent(
                        call.argument<String>("company") ?: "",
                        call.argument<Boolean>("guided") == true,
                        capture(call),
                    )
                    result.success(keep(consent))
                }
                "buildInfo" -> result.success(GaiaDeskEmbed.buildInfo)
                else -> result.notImplemented()
            }
        } catch (e: GaiaDeskEmbedException) {
            result.error(e.code, e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("bad_config", e.message ?: "bad arguments", null)
        } catch (e: UnsatisfiedLinkError) {
            result.error("native_missing", "the GaiaDesk embed library is not in this build: ${e.message}", null)
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val act = activity ?: return result.error("no_activity", "gaiadesk_embed needs a foreground activity to share", null)
        val capture = capture(call)
        val config = GaiaDeskEmbed.Configuration(
            embedToken = call.argument<String>("embedToken") ?: "",
            company = call.argument<String>("company") ?: "",
            server = call.argument<String>("server"),
            guided = call.argument<Boolean>("guided") == true,
            fps = call.argument<Int>("fps") ?: 15,
            maskedRects = rects(call.argument<List<Map<String, Number>>>("masks")),
            capture = capture,
        )
        val consent = call.argument<String>("consent")?.let { consents.remove(it) }
            ?: return result.error("consent_required", "ask your user first (requestConsent, or recordConsent after your own dialog); a consent starts one session", null)
        val id = nextId++
        val embed = GaiaDeskEmbed.start(act, config, consent) { e ->
            if (e is GaiaDeskEmbed.Event.Ended) sessions.remove(id)
            send(id, toMap(e))
        }
        sessions[id] = embed
        result.success(id)
    }

    private fun requestConsent(call: MethodCall, result: MethodChannel.Result) {
        val act = activity ?: return result.error("no_activity", "gaiadesk_embed needs a foreground activity to ask", null)
        GaiaDeskEmbed.requestConsent(
            act,
            call.argument<String>("company") ?: "",
            call.argument<Boolean>("guided") == true,
            capture(call),
        ) { consent -> result.success(consent?.let { keep(it) }) }
    }

    private fun capture(call: MethodCall): GaiaDeskEmbed.Capture =
        if (call.argument<String>("capture") == "screen") GaiaDeskEmbed.Capture.SCREEN else GaiaDeskEmbed.Capture.APP

    /**
     * Dart's logical pixels (from the Flutter view's top-left) → window pixels.
     * Without an activity and its Flutter view there is no density or offset to
     * convert with, and a guess (density 1, offset 0) would mask the wrong
     * place: refused (`no_activity`) instead.
     */
    private fun rects(raw: List<Map<String, Number>>?): List<RectF> {
        if (raw.isNullOrEmpty()) return emptyList()
        val act = activity
            ?: throw GaiaDeskEmbedException("no_activity", "gaiadesk_embed needs a foreground activity to place masks")
        val view = act.window?.decorView?.let { flutterView(it) }
            ?: throw GaiaDeskEmbedException("no_activity", "gaiadesk_embed found no Flutter view to place masks in")
        val density = act.resources.displayMetrics.density
        val at = IntArray(2)
        view.getLocationInWindow(at)
        return raw.map { r ->
            val x = (r["x"]?.toFloat() ?: 0f) * density + at[0]
            val y = (r["y"]?.toFloat() ?: 0f) * density + at[1]
            val w = (r["w"]?.toFloat() ?: 0f) * density
            val h = (r["h"]?.toFloat() ?: 0f) * density
            RectF(x, y, x + w, y + h)
        }
    }

    private fun flutterView(v: View): FlutterView? {
        if (v is FlutterView) return v
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) flutterView(v.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun send(id: Int, event: Map<String, Any?>) {
        val msg = mapOf("session" to id, "event" to event)
        val s = sink
        if (s != null) {
            s.success(msg)
        } else if (pending.size < 256) {
            pending.addLast(msg)
        }
    }

    private fun stopAll() {
        sessions.values.toList().forEach { it.stop() }
    }

    companion object {
        /** One SDK event as the library's JSON shape. */
        fun toMap(e: GaiaDeskEmbed.Event): Map<String, Any?> = when (e) {
            is GaiaDeskEmbed.Event.State -> mapOf("type" to "state", "state" to e.state)
            is GaiaDeskEmbed.Event.Code -> mapOf("type" to "code", "code" to e.code, "session_id" to e.sessionId, "mode" to e.mode)
            is GaiaDeskEmbed.Event.Joined -> mapOf("type" to "joined", "agent" to e.agent)
            is GaiaDeskEmbed.Event.Left -> mapOf("type" to "left")
            is GaiaDeskEmbed.Event.Control -> mapOf("type" to "control", "allowed" to e.allowed)
            is GaiaDeskEmbed.Event.Action -> mapOf("type" to "action", "action" to e.action, "applied" to e.applied, "reason" to e.reason)
            is GaiaDeskEmbed.Event.Error -> mapOf("type" to "error", "code" to e.code, "message" to e.message)
            is GaiaDeskEmbed.Event.Ended -> mapOf("type" to "ended", "reason" to e.reason)
        }
    }
}
