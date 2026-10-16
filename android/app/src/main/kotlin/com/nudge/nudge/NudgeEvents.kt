package com.nudge.nudge

import io.flutter.plugin.common.EventChannel

/** Bridge that lets the background service push triggers into Flutter. */
object NudgeEvents {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink?) {
        sink = eventSink
    }

    fun emit(trigger: String) {
        sink?.success(trigger)
    }
}
