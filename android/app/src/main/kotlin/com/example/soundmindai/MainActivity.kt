package com.example.soundmindai

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var equalizerPlugin: EqualizerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        equalizerPlugin = EqualizerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        equalizerPlugin?.release()
        equalizerPlugin = null
        super.onDestroy()
    }
}