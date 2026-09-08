package com.example.soundmindai

import android.content.Context
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EqualizerPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "EqualizerPlugin"
        private const val CHANNEL_NAME = "com.soundmindai.equalizer"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null

    private var currentSessionId: Int = 0
    private var isEnabled: Boolean = false
    private var preampGainMillibels: Int = 0
    private var bassBoostStrength: Int = 0
    private val baseBandLevels = mutableMapOf<Int, Int>()

    private var minBandLevel: Short = -1500
    private var maxBandLevel: Short = 1500

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "attachToSession" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val success = attachToSession(sessionId)
                    if (success) {
                        result.success(getDeviceCapabilities())
                    } else {
                        result.error("INIT_FAILED", "Failed to initialize native audio effects for session $sessionId", null)
                    }
                }
                "release" -> {
                    release()
                    result.success(true)
                }
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    setEnabled(enabled)
                    result.success(true)
                }
                "getNumberOfBands" -> {
                    val count = equalizer?.numberOfBands?.toInt() ?: 0
                    result.success(count)
                }
                "getBandLevelRange" -> {
                    val range = getBandLevelRange()
                    result.success(range)
                }
                "getBandFreqRange" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val range = getBandFreqRange(band)
                    result.success(range)
                }
                "getCenterFreq" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val freq = equalizer?.getCenterFreq(band.toShort()) ?: 0
                    result.success(freq)
                }
                "setBandLevel" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val levelMillibels = call.argument<Int>("levelMillibels") ?: 0
                    setBandLevel(band, levelMillibels)
                    result.success(true)
                }
                "setAllBandLevels" -> {
                    val levels = call.argument<List<Int>>("levels") ?: emptyList()
                    setAllBandLevels(levels)
                    result.success(true)
                }
                "setPreampGain" -> {
                    val gainMillibels = call.argument<Int>("gainMillibels") ?: 0
                    setPreampGain(gainMillibels)
                    result.success(true)
                }
                "setBassBoostStrength" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    setBassBoostStrength(strength)
                    result.success(true)
                }
                "getDeviceCapabilities" -> {
                    result.success(getDeviceCapabilities())
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing ${call.method}: ${e.message}", e)
            result.error("ERROR", e.localizedMessage, null)
        }
    }

    private fun attachToSession(sessionId: Int): Boolean {
        if (sessionId <= 0) {
            Log.w(TAG, "Invalid audio session ID: $sessionId")
            return false
        }

        if (sessionId == currentSessionId && equalizer != null) {
            Log.d(TAG, "Already attached to session $sessionId")
            return true
        }

        releaseEffects()
        currentSessionId = sessionId

        return try {
            // Priority 0 means standard priority
            val eq = Equalizer(0, sessionId)

            val range = eq.bandLevelRange
            if (range != null && range.size >= 2) {
                minBandLevel = range[0]
                maxBandLevel = range[1]
            }

            equalizer = eq

            // Pre-apply stored band levels and preamp BEFORE enabling equalizer
            // so native filters are initialized with smooth, settled coefficients
            applyAllBandLevelsWithPreamp()
            eq.enabled = isEnabled

            try {
                val bb = BassBoost(0, sessionId)
                if (bb.strengthSupported) {
                    bb.setStrength(bassBoostStrength.coerceIn(0, 1000).toShort())
                }
                bb.enabled = isEnabled && bassBoostStrength > 0
                bassBoost = bb
            } catch (e: Exception) {
                Log.w(TAG, "BassBoost unsupported or failed to init: ${e.message}")
            }

            Log.i(TAG, "Successfully attached native effects to session $sessionId with ${eq.numberOfBands} bands")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create Equalizer on session $sessionId: ${e.message}", e)
            releaseEffects()
            false
        }
    }

    private fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
        if (enabled) {
            // Re-apply band levels before enabling so transition is smooth
            applyAllBandLevelsWithPreamp()
        }
        try {
            equalizer?.enabled = enabled
        } catch (e: Exception) {
            Log.w(TAG, "Failed to toggle Equalizer: ${e.message}")
        }
        try {
            bassBoost?.enabled = enabled && bassBoostStrength > 0
        } catch (e: Exception) {
            Log.w(TAG, "Failed to toggle BassBoost: ${e.message}")
        }
    }

    private fun setBandLevel(band: Int, levelMillibels: Int) {
        baseBandLevels[band] = levelMillibels
        applyBandLevelWithPreamp(band)
    }

    private fun setAllBandLevels(levels: List<Int>) {
        levels.forEachIndexed { index, level ->
            baseBandLevels[index] = level
        }
        applyAllBandLevelsWithPreamp()
    }

    private fun setPreampGain(gainMillibels: Int) {
        preampGainMillibels = gainMillibels
        applyAllBandLevelsWithPreamp()
    }

    private fun setBassBoostStrength(strength: Int) {
        bassBoostStrength = strength.coerceIn(0, 1000)
        try {
            bassBoost?.let {
                if (it.strengthSupported) {
                    it.setStrength(bassBoostStrength.toShort())
                }
                it.enabled = isEnabled && bassBoostStrength > 0
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set BassBoost strength: ${e.message}")
        }
    }

    private fun applyBandLevelWithPreamp(band: Int) {
        val eq = equalizer ?: return
        try {
            val baseLevel = baseBandLevels[band] ?: 0
            val effectiveLevel = (baseLevel + preampGainMillibels).coerceIn(minBandLevel.toInt(), maxBandLevel.toInt()).toShort()
            eq.setBandLevel(band.toShort(), effectiveLevel)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set band $band level: ${e.message}")
        }
    }

    private fun applyAllBandLevelsWithPreamp() {
        val eq = equalizer ?: return
        try {
            val numBands = eq.numberOfBands.toInt()
            for (band in 0 until numBands) {
                val baseLevel = baseBandLevels[band] ?: 0
                val effectiveLevel = (baseLevel + preampGainMillibels).coerceIn(minBandLevel.toInt(), maxBandLevel.toInt()).toShort()
                eq.setBandLevel(band.toShort(), effectiveLevel)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to apply all band levels with preamp: ${e.message}")
        }
    }

    private fun getBandLevelRange(): List<Int> {
        val eq = equalizer
        if (eq != null) {
            try {
                val range = eq.bandLevelRange
                if (range != null && range.size >= 2) {
                    return listOf(range[0].toInt(), range[1].toInt())
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error getting bandLevelRange: ${e.message}")
            }
        }
        return listOf(minBandLevel.toInt(), maxBandLevel.toInt())
    }

    private fun getBandFreqRange(band: Int): List<Int> {
        val eq = equalizer ?: return listOf(0, 0)
        return try {
            val range = eq.getBandFreqRange(band.toShort())
            if (range != null && range.size >= 2) {
                listOf(range[0], range[1])
            } else {
                listOf(0, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error getting bandFreqRange for band $band: ${e.message}")
            listOf(0, 0)
        }
    }

    private fun getDeviceCapabilities(): Map<String, Any> {
        val eq = equalizer
        val isSupported = eq != null
        val numBands = eq?.numberOfBands?.toInt() ?: 0
        val levelRange = getBandLevelRange()

        val bandsList = mutableListOf<Map<String, Any>>()
        if (eq != null) {
            for (i in 0 until numBands) {
                try {
                    val centerFreq = eq.getCenterFreq(i.toShort())
                    val freqRange = getBandFreqRange(i)
                    val curLevel = try { eq.getBandLevel(i.toShort()).toInt() } catch (_: Exception) { 0 }
                    bandsList.add(
                        mapOf(
                            "index" to i,
                            "centerFreq" to centerFreq,
                            "freqRange" to freqRange,
                            "level" to curLevel
                        )
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Error reading band $i info: ${e.message}")
                }
            }
        }

        return mapOf(
            "isSupported" to isSupported,
            "numberOfBands" to numBands,
            "bandLevelRange" to levelRange,
            "bands" to bandsList,
            "bassBoostSupported" to (bassBoost?.strengthSupported ?: false)
        )
    }

    private fun releaseEffects() {
        try {
            equalizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing Equalizer: ${e.message}")
        }
        equalizer = null

        try {
            bassBoost?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing BassBoost: ${e.message}")
        }
        bassBoost = null

        try {
            virtualizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing Virtualizer: ${e.message}")
        }
        virtualizer = null
    }

    fun release() {
        channel.setMethodCallHandler(null)
        releaseEffects()
        currentSessionId = 0
    }
}
