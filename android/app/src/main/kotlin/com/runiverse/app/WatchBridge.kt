package com.runiverse.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart(`lib/core/watch/watch_channel.dart`)와 갤럭시워치 사이 통로.
 * 메시지 형식과 보내는 규칙은 워치 레포 `docs/phone-communication.md`가 정본이다.
 *
 * 본문은 Dart가 만든 JSON 문자열을 그대로 싣는다 — 여기서는 해석하지 않는다.
 */
class WatchBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val messageClient = Wearable.getMessageClient(context)
    private val nodeClient = Wearable.getNodeClient(context)
    private val methodChannel = MethodChannel(messenger, "watch")
    private val eventChannel = EventChannel(messenger, "watch/messages")

    // 지금 구독 중인 Dart 쪽. 받기 등록이 실패했을 때 다시 걸려고 들고 있는다.
    private var sink: EventChannel.EventSink? = null
    private var listener: MessageClient.OnMessageReceivedListener? = null
    private var registration: Task<Void>? = null

    // 받기 등록이 끝났는지. launchApp은 이게 true일 때만 워치 앱을 켠다 —
    // 켜자마자 워치가 보내는 WATCH_SYNC를 놓치지 않기 위해서다.
    private var listening = false

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sink = null
        stopListening()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> send(call.arguments as String, result)
            "launchApp" -> launchApp(result)
            else -> result.notImplemented()
        }
    }

    // 결과 값은 Dart `WatchSendResult.fromWire`가 읽는다.
    // SENT는 Play 서비스가 보내기를 받아들였다는 뜻이지 워치가 받았다는 뜻이 아니다.
    // 못 받은 메시지는 워치가 3초 감시와 WATCH_SYNC로 다시 맞춘다.
    private fun send(body: String, result: MethodChannel.Result) {
        withNearbyWatch(
            onFound = { watchId ->
                messageClient.sendMessage(watchId, PATH, body.toByteArray(Charsets.UTF_8))
                    .addOnSuccessListener { result.success("SENT") }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "워치로 보내기 실패", e)
                        result.success("FAILED")
                    }
            },
            onNone = { result.success("NO_WATCH") },
            onError = { e ->
                Log.w(TAG, "연결된 워치 조회 실패", e)
                result.success("FAILED")
            },
        )
    }

    // 결과 값은 Dart `WatchLaunchResult.fromWire`가 읽는다.
    // LAUNCHED는 워치에 실행 요청이 넘어갔다는 뜻이다. 화면이 떴다는 뜻은 아니다.
    // 워치부터 찾는다 — 워치 앱이 없는 폰이 NOT_LISTENING이 아니라 NO_WATCH를 받도록.
    private fun launchApp(result: MethodChannel.Result) {
        withNearbyWatch(
            onFound = onFound@{ watchId ->
                // 구독 전이거나 워치를 찾는 사이 구독이 끊겼으면 켜지 않는다 — 켜도 첫 SYNC를 못 받는다
                if (!listening) {
                    result.success("NOT_LISTENING")
                    return@onFound
                }
                // 폰과 워치는 applicationId가 같다 — dev 폰은 dev 워치 앱을 켠다
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("runiverse://${context.packageName}"))
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                val executor = ContextCompat.getMainExecutor(context)
                val future = RemoteActivityHelper(context, executor).startRemoteActivity(intent, watchId)
                future.addListener({
                    try {
                        future.get()
                        result.success("LAUNCHED")
                    } catch (e: Exception) {
                        Log.w(TAG, "워치 앱 켜기 실패", e)
                        result.success("FAILED")
                    }
                }, executor)
            },
            onNone = { result.success("NO_WATCH") },
            onError = { e ->
                Log.w(TAG, "연결된 워치 조회 실패", e)
                result.success("FAILED")
            },
        )
    }

    // 보낼 때마다 묻는다 — 워치는 러닝 중에도 꺼지거나 멀어진다.
    // 폰 안의 Play 서비스에 묻는 것이라 블루투스 왕복은 없다.
    // 워치는 한 대만 쓴다 — 가까이 있는 첫 번째로 보낸다.
    private fun withNearbyWatch(
        onFound: (String) -> Unit,
        onNone: () -> Unit,
        onError: (Exception) -> Unit,
    ) {
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes ->
                val watch = nodes.firstOrNull { it.isNearby }
                if (watch == null) {
                    onNone()
                } else {
                    retryListeningIfUnavailable()
                    onFound(watch.id)
                }
            }
            .addOnFailureListener { e -> if (e.isWearableUnavailable()) onNone() else onError(e) }
    }

    // 워치가 보이는데 받기 등록이 17로 실패해 있으면 다시 건다 — 17은 워치가 있어도 잠깐 날 수 있다.
    // 보내기·켜기가 없으면 다시 걸 기회도 없다. 다른 실패는 LISTEN_FAILED로 이미 알렸다.
    private fun retryListeningIfUnavailable() {
        val events = sink ?: return
        val last = registration ?: return
        if (last.isComplete && last.exception?.isWearableUnavailable() == true) listen(events)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        listen(events)
    }

    private fun listen(events: EventChannel.EventSink) {
        stopListening()
        // 구독마다 새 리스너를 만든다. 앞 구독의 해제가 늦게 끝나도 이번 등록을 지우지 않는다.
        val newListener = MessageClient.OnMessageReceivedListener { event ->
            if (event.path != PATH) return@OnMessageReceivedListener
            events.success(String(event.data, Charsets.UTF_8))
        }
        val newRegistration = messageClient.addListener(newListener)
            .addOnSuccessListener { if (listener === newListener) listening = true }
            .addOnFailureListener { e ->
                // 워치에 닿을 수 없다 — 오류로 올리지 않고, 워치가 보이면 다시 건다
                if (e.isWearableUnavailable()) return@addOnFailureListener
                Log.w(TAG, "받기 등록 실패", e)
                if (listener === newListener) events.error("LISTEN_FAILED", e.message, null)
            }
        listener = newListener
        registration = newRegistration
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stopListening()
    }

    private fun stopListening() {
        val old = listener ?: return
        val oldRegistration = registration
        listener = null
        registration = null
        listening = false
        // 등록이 진행 중이어도 끝까지 간다 — 등록이 끝난 뒤에 해제해야 리스너가 남지 않는다
        oldRegistration?.addOnCompleteListener {
            messageClient.removeListener(old)
                .addOnFailureListener { e -> if (!e.isWearableUnavailable()) Log.w(TAG, "받기 해제 실패", e) }
        }
    }

    // 17: Wearable API에 붙지 못했다. 워치 앱(Galaxy Wearable·Wear OS 앱)이 없는 폰은 늘 이렇고,
    // 워치가 있어도 Play 서비스가 잠깐 못 붙으면 난다 — 어느 쪽이든 지금은 워치에 닿을 수 없으니 "워치 없음"으로 본다
    private fun Exception.isWearableUnavailable() =
        this is ApiException && statusCode == CommonStatusCodes.API_NOT_CONNECTED

    private companion object {
        const val TAG = "WatchBridge"
        const val PATH = "/running"
    }
}
