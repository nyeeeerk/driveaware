import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

/// Hybrid TTS: ElevenLabs for rich voice, flutter_tts as instant fallback.
/// 
/// Use [speak] for normal speech (tries ElevenLabs first).
/// Use [speakUrgent] for safety-critical alerts (always uses on-device TTS, zero latency).
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _elevenLabsAvailable = true;

  Future<void> init() async {
    // Init on-device TTS (fallback + urgent alerts)
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(0.7);

    // Test ElevenLabs availability
    _elevenLabsAvailable = AppConstants.elevenLabsApiKey != "YOUR_ELEVENLABS_API_KEY" 
        && AppConstants.elevenLabsApiKey.isNotEmpty;
    
    debugPrint('🔊 TTS init: ElevenLabs ${_elevenLabsAvailable ? "enabled" : "disabled (no API key)"}');
  }

  /// Normal speech — tries ElevenLabs, falls back to flutter_tts on failure.
  Future<void> speak(String text) async {
    if (_elevenLabsAvailable) {
      try {
        await _speakElevenLabs(text);
        return;
      } catch (e) {
        debugPrint('🔊 ElevenLabs failed, using device TTS: $e');
      }
    }
    await _speakDevice(text);
  }

  /// Urgent speech — always uses on-device TTS for zero latency.
  Future<void> speakUrgent(String text) async {
    await _speakDevice(text);
  }

  /// ElevenLabs API call → play audio
  Future<void> _speakElevenLabs(String text) async {
    final url = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/${AppConstants.elevenLabsVoiceId}'
    );

    final body = jsonEncode({
      'text': text,
      'model_id': 'eleven_turbo_v2_5',
      'voice_settings': {
        'stability': 0.5,
        'similarity_boost': 0.75,
      },
    });

    debugPrint('🔊 ElevenLabs request: ${text.substring(0, text.length.clamp(0, 50))}...');

    final response = await http.post(
      url,
      headers: {
        'xi-api-key': AppConstants.elevenLabsApiKey,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      },
      body: body,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      debugPrint('🔊 ElevenLabs error ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
      throw Exception('ElevenLabs API error: ${response.statusCode}');
    }

    debugPrint('🔊 ElevenLabs audio received: ${response.bodyBytes.length} bytes');

    // Write audio to temp file and play
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(response.bodyBytes);
    
    await _audioPlayer.stop(); // Stop any previous playback
    await _audioPlayer.setFilePath(file.path);
    await _audioPlayer.play();
    
    // Wait for playback to finish
    try {
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      debugPrint('🔊 Audio playback timed out or was interrupted');
    }

    // Clean up temp file
    try { await file.delete(); } catch (_) {}
  }

  /// On-device flutter_tts with completion waiting
  Future<void> _speakDevice(String text) async {
    Completer<void> completer = Completer<void>();

    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    _flutterTts.setCancelHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    _flutterTts.setErrorHandler((msg) {
      if (!completer.isCompleted) completer.complete(); // Don't throw, just move on so loop continues
    });

    try {
      await _flutterTts.speak(text);
      await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}