import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:just_audio/just_audio.dart';
import '../services/face_detector.dart';
import '../services/location_service.dart';
import '../services/ai_service.dart';
import '../services/tts_stt_service.dart';
import '../services/connectivity_service.dart';
import '../models/driver_state.dart';
import '../models/place_model.dart';
import '../managers/drowsiness_manager.dart';
import '../constants.dart';

class MonitoringController extends ChangeNotifier {
  final VoidCallback onRequireAlertPopup;
  final CalibrationData calibration;

  late DrowsinessManager _drowsinessManager;
  final LocationService _locationService = LocationService();
  final AIService _aiService = AIService();
  final TtsService _ttsService = TtsService();
  final ConnectivityService _connectivity = ConnectivityService();
  final SpeechToText _speech = SpeechToText();

  bool isListening = false;
  bool isTalking = false;
  bool isNightMode = false;
  bool _isManualNightMode = false; // Prevents auto-ambient detection from overriding user
  bool isAlarmPlaying = false;
  DriverStatus status = DriverStatus.normal;
  String message = "\"I'm watching the road with you.\"";

  // Alert cooldown to prevent spam
  DateTime? _lastWarningTime;

  // Track active alert sequence to prevent overlaps
  int _alertSessionId = 0;

  // Alarm player for sleeping alert
  final AudioPlayer _alarmPlayer = AudioPlayer();

  DrowsinessResult? lastResult;

  MonitoringController({
    required this.calibration,
    required this.onRequireAlertPopup,
  }) {
    _initServicesAndStart();
  }

  Future<void> _initServicesAndStart() async {
    await WakelockPlus.enable();
    await _ttsService.init();
    await _speech.initialize();

    _drowsinessManager = DrowsinessManager(
      calibration: calibration,
      onStatusChanged: _handleStatusChange,
      onResultUpdated: (result) {
        lastResult = result;
        notifyListeners();
      },
      onNightModeChanged: _handleNightModeChange,
    );
    
    await _drowsinessManager.init();
    _drowsinessManager.startMonitoring();
    _locationService.startTracking();
  }

  // Helper to determine alert priority
  int _getPriority(DriverStatus s) {
    switch (s) {
      case DriverStatus.normal: return 0;
      case DriverStatus.warning: return 1;
      case DriverStatus.critical: return 2;
      case DriverStatus.sleeping: return 3;
    }
  }

  void _handleStatusChange(DriverStatus newStatus) {
    if (status == newStatus) return;
    
    // Priority check for interrupting TTS
    if (isTalking) {
      if (_getPriority(newStatus) > _getPriority(status)) {
        print('🚦 INTERRUPTING lower-priority speech for $newStatus');
        _ttsService.stop(); 
        isTalking = false;
      } else {
        return; // Blocked: Currently speaking a higher or equal priority alert
      }
    }

    status = newStatus;
    _alertSessionId++; // Cancel any currently running async alert sequence
    notifyListeners();

    // Route to the correct alert
    switch (newStatus) {
      case DriverStatus.warning:
        // Cooldown
        final cooldown = AppConstants.warningCooldown;
        final now = DateTime.now();
        if (_lastWarningTime != null && now.difference(_lastWarningTime!).inSeconds < cooldown) {
          break; // Skip, too soon
        }
        _lastWarningTime = now;
        _triggerWarningAlert();
        break;
      case DriverStatus.critical:
        _triggerCriticalAlert();
        break;
      case DriverStatus.sleeping:
        onRequireAlertPopup();
        _triggerSleepingAlarm();
        break;
      case DriverStatus.normal:
        // Optional: Handle returning to normal state
        break;
    }
  }

  Future<void> _triggerWarningAlert() async {
    final int sessionId = _alertSessionId;
    isTalking = true;
    notifyListeners();

    String warningSpeech = "Warning, early signs of fatigue.";
    if (lastResult?.isYawDistracted == true) {
      warningSpeech = "Distraction warning. Please keep your eyes centered on the road.";
    } else if (lastResult?.isRollSlumped == true) {
      warningSpeech = "Posture warning. Please maintain an upright sitting posture.";
    } else if (lastResult?.isFaceOccluded == true) {
      warningSpeech = "Face tracking lost. Please ensure your face is visible to the camera.";
    } else if (lastResult?.isPitchWarning == true) {
      warningSpeech = "Head nodding detected. Please keep your head up.";
    }

    await _ttsService.speakUrgent(warningSpeech);
    if (sessionId != _alertSessionId) return;

    // Check connectivity before making API calls
    final online = await _connectivity.isOnline;
    if (!online) {
      message = "You seem tired. Please consider pulling over.";
      notifyListeners();
      await _ttsService.speakUrgent(message);
      if (sessionId == _alertSessionId) isTalking = false;
      return;
    }

    message = "Analyzing nearby rest stops...";
    notifyListeners();
    
    try {
      final pos = await _locationService.getCurrentLocation();
      final PlaceModel? nearestStop = await _locationService.findNearestStop(pos.latitude, pos.longitude);
      if (sessionId != _alertSessionId) return;
      
      if (nearestStop != null) {
        final distanceStr = nearestStop.distanceKm.toStringAsFixed(1);
        final stopMessage = "You seem tired. Consider stopping at ${nearestStop.name}, $distanceStr kilometers ahead.";
        message = stopMessage;
        notifyListeners();
        await _ttsService.speak(stopMessage);
      } else {
        message = "You seem a bit tired, should we find a place to stop?";
        notifyListeners();
        await _ttsService.speak(message);
      }
    } catch (e) {
      print("🚨 Warning Alert Location Error: $e");
      if (sessionId != _alertSessionId) return;
      message = "You seem a bit tired, should we find a place to stop?";
      notifyListeners();
      await _ttsService.speak(message);
    }
    if (sessionId == _alertSessionId) isTalking = false;
  }

  Future<void> _triggerCriticalAlert() async {
    final int sessionId = _alertSessionId;
    isTalking = true;
    notifyListeners();

    String criticalSpeech = "Fatigue detected.";
    if (lastResult?.isHeadBobbing == true) {
      criticalSpeech = "Repeated head nodding detected. Critical fatigue.";
    } else if (lastResult?.isPitchCritical == true) {
      criticalSpeech = "Critical head drop detected. Please pull over.";
    }

    await _ttsService.speakUrgent(criticalSpeech);
    if (sessionId != _alertSessionId) return;

    // Check connectivity before making API calls
    final online = await _connectivity.isOnline;
    if (!online) {
      message = "\"Pull over immediately.\"";
      notifyListeners();
      await _ttsService.speakUrgent("Pull over immediately. Find a safe place to stop.");
      if (sessionId == _alertSessionId) isTalking = false;
      return;
    }

    message = "\"Analyzing route for safe stops...\"";
    notifyListeners();
    
    try {
      final pos = await _locationService.getCurrentLocation();
      final PlaceModel? nearestStop = await _locationService.findNearestStop(pos.latitude, pos.longitude);
      if (sessionId != _alertSessionId) return;
      
      if (nearestStop != null) {
        final distanceStr = nearestStop.distanceKm.toStringAsFixed(1);
        final alertMessage = "Critical fatigue detected. Pull over at ${nearestStop.name}, $distanceStr kilometers away.";
        message = "\"$alertMessage\"";
        notifyListeners();
        await _ttsService.speak(alertMessage);
      } else {
        message = "\"Pull over immediately.\"";
        notifyListeners();
        await _ttsService.speakUrgent("Pull over immediately. No safe stops found nearby.");
      }
    } catch (e) {
      print("🚨 Critical Alert Location Error: $e");
      if (sessionId != _alertSessionId) return;
      message = "\"Pull over immediately.\"";
      notifyListeners();
      await _ttsService.speakUrgent("Pull over immediately.");
    }
    if (sessionId == _alertSessionId) isTalking = false;
  }

  Future<void> _triggerSleepingAlarm() async {
    final int sessionId = _alertSessionId;
    await _ttsService.stop();
    isTalking = true;
    message = "\"Hey! Are you okay?\"";
    notifyListeners();

    // Step 1: TARS asks if the driver is okay
    await _ttsService.speakUrgent("Hey! Are you okay? Say something if you can hear me.");
    if (sessionId != _alertSessionId) return;

    // Step 2: Listen for a response (8 second timeout)
    final String? driverResponse = await _listenForResponse(const Duration(seconds: 8));
    if (sessionId != _alertSessionId) return;

    final bool hasRealResponse = driverResponse != null
        && driverResponse.trim().length >= 3
        && RegExp(r'[a-zA-Z]').hasMatch(driverResponse);
    if (hasRealResponse) {
      // Driver responded — have a conversation
      debugPrint('🗣️ Driver responded during sleeping alert: $driverResponse');
      message = "\"Processing...\"";
      notifyListeners();

      try {
        String loc = await _locationService.getCurrentAddress();
        PlaceModel? stop;
        try {
          final pos = await _locationService.getCurrentLocation();
          stop = await _locationService.findNearestStop(pos.latitude, pos.longitude);
        } catch (_) {}

        String response = await _aiService.chatWithTars(
          "The driver was detected as falling asleep while driving. They just woke up and said: \"$driverResponse\". Respond with concern and urgency IN CONVERSATIONAL TAGALOG (Taglish). Suggest they pull over.",
          location: loc,
          nearestStop: stop,
        );
        if (sessionId != _alertSessionId) return;

        message = "\"$response\"";
        notifyListeners();
        await _ttsService.speak(response);

        // Enter continuous conversation loop
        startListening();
      } catch (e) {
        debugPrint('🚨 Sleeping conversation error: $e');
        if (sessionId != _alertSessionId) return;
        message = "\"Please pull over and rest.\"";
        notifyListeners();
        await _ttsService.speakUrgent("Please pull over and rest.");
      }
    } else {
      // No response — escalate with alarm
      debugPrint('🚨 No response from driver — starting alarm');
      await _startAlarm();
      if (sessionId != _alertSessionId) return;

      message = "\"DRIVER UNRESPONSIVE. PULL OVER IMMEDIATELY.\"";
      notifyListeners();
      await _ttsService.speakUrgent("Driver unresponsive. Pull over immediately.");
      if (sessionId != _alertSessionId) return;

      // Try to find a safe stop
      try {
        final pos = await _locationService.getCurrentLocation();
        final nearestStop = await _locationService.findNearestStop(pos.latitude, pos.longitude);
        if (sessionId != _alertSessionId) return;
        
        if (nearestStop != null) {
          final distanceStr = nearestStop.distanceKm.toStringAsFixed(1);
          final alertMessage = "Head to ${nearestStop.name}, $distanceStr kilometers away.";
          message = "\"$alertMessage\"";
          notifyListeners();
          await _ttsService.speak(alertMessage);
        }
      } catch (e) {
        debugPrint('🚨 Sleeping Alarm Location Error: $e');
      }
    }
    if (sessionId == _alertSessionId) isTalking = false;
  }

  /// Listen for a voice response with a timeout.
  /// Returns the recognized text, or null if no response.
  Future<String?> _listenForResponse(Duration timeout) async {
    if (!_speech.isAvailable) return null;

    final completer = Completer<String?>();
    Timer? timeoutTimer;
    String lastWords = "";

    isListening = true;
    message = "\"Listening...\"";
    notifyListeners();

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _speech.stop();
        isListening = false;
        notifyListeners();
        // In a noisy car, finalResult might never fire before timeout.
        // If we heard anything, use it.
        completer.complete(null); // Timeout with no final result = no response
      }
    });

    // CRITICAL: Give the OS half a second to release the speaker Audio Focus
    // from the TTS engine before claiming the microphone, otherwise the native
    // STT "beep" will deadlock the microphone route on some devices.
    await Future.delayed(const Duration(milliseconds: 500));

    await _speech.listen(
      onResult: (result) {
        lastWords = result.recognizedWords;
        if (result.finalResult && !completer.isCompleted) {
          timeoutTimer?.cancel();
          isListening = false;
          notifyListeners();
          completer.complete(result.recognizedWords);
        }
      },
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
    );

    return completer.future;
  }

  Future<void> _startAlarm() async {
    try {
      await _alarmPlayer.setAsset('assets/audio/alert.mp3');
      await _alarmPlayer.setLoopMode(LoopMode.one);
      await _alarmPlayer.setVolume(1.0);
      await _alarmPlayer.play();
      isAlarmPlaying = true;
      notifyListeners();
      debugPrint('🔔 Alarm started');
    } catch (e) {
      debugPrint('🔔 Alarm failed to play: $e');
    }
  }

  Future<void> stopAlarm() async {
    if (!isAlarmPlaying) return;
    await _alarmPlayer.stop();
    isAlarmPlaying = false;
    notifyListeners();
    debugPrint('🔔 Alarm stopped');
  }

  void startListening() async {
    if (!_speech.isAvailable || isListening) return;
    
    _alertSessionId++; // Cancel active async alerts to ensure clean listening state
    _ttsService.stop();

    final String? response = await _listenForResponse(const Duration(seconds: 10));

    if (response != null && response.isNotEmpty) {
      _processVoiceCommand(response);
    } else {
      _aiService.endConversation();
      message = "\"I'm watching the road with you.\"";
      notifyListeners();
    }
  }

  Future<void> _processVoiceCommand(String text) async {
    if (text.isEmpty) return;
    
    // Check if the user wants to end the conversation
    final isEndCommand = RegExp(r'\b(stop|salamat|bye|cancel|tama na|goodbye|quit|exit)\b', caseSensitive: false).hasMatch(text);
    
    message = "THINKING...";
    notifyListeners();

    String loc = await _locationService.getCurrentAddress();
    PlaceModel? stop;
    try {
      final pos = await _locationService.getCurrentLocation();
      stop = await _locationService.findNearestStop(pos.latitude, pos.longitude);
    } catch (e) {
      print("🚨 Voice Command Location Error: $e");
    }

    String response = await _aiService.chatWithTars(text, location: loc, nearestStop: stop);
    
    message = "\"$response\"";
    notifyListeners();
    // Wait for the TTS to finish speaking entirely before making decisions
    await _ttsService.speak(response);
    
    if (isEndCommand) {
      _aiService.endConversation();
      Future.delayed(const Duration(seconds: 4), () {
        message = "\"I'm watching the road with you.\"";
        notifyListeners();
      });
    } else {
      // Create the continuous walkie-talkie loop!
      startListening();
    }
  }

  Future<void> findCoffeeAction() async {
    final int sessionId = ++_alertSessionId;
    
    await stopAlarm();
    await _ttsService.stop();
    isTalking = true;
    message = "Searching for nearby coffee...";
    notifyListeners();

    await _ttsService.speakUrgent("Searching for a nearby coffee shop.");
    if (sessionId != _alertSessionId) return;

    try {
      final pos = await _locationService.getCurrentLocation();
      final coffeeShop = await _locationService.findNearestCoffee(pos.latitude, pos.longitude);
      
      if (sessionId != _alertSessionId) return;

      if (coffeeShop != null) {
        final distanceStr = coffeeShop.distanceKm.toStringAsFixed(1);
        final announceMessage = "Found ${coffeeShop.name}, $distanceStr kilometers away. Please proceed.";
        message = announceMessage;
        notifyListeners();
        await _ttsService.speak(announceMessage);
      } else {
        message = "No coffee shops found nearby.";
        notifyListeners();
        await _ttsService.speak("I couldn't find any coffee shops nearby.");
      }
    } catch (e) {
      debugPrint("🚨 Coffee Action Error: $e");
      if (sessionId != _alertSessionId) return;
      message = "Location error.";
      notifyListeners();
      await _ttsService.speak("I couldn't connect to the location service to find coffee.");
    }
    
    if (sessionId == _alertSessionId) isTalking = false;
  }

  // ─────────────────────────────────────────
  // NIGHT/LIGHT MODE
  // ─────────────────────────────────────────

  void toggleNightMode() {
    isNightMode = !isNightMode;
    _isManualNightMode = true; // Lock in the user's choice
    notifyListeners();
  }

  void _handleNightModeChange(bool autoNightMode) {
    if (_isManualNightMode) return; // Don't let the camera override manual toggles
    if (isNightMode == autoNightMode) return;
    
    isNightMode = autoNightMode;
    notifyListeners();

    if (autoNightMode) {
      _ttsService.speak("Night driving detected. I'll keep a closer watch.");
    } else {
      _ttsService.speak("Switching to day mode.");
    }
  }



  @override
  void dispose() {
    _drowsinessManager.stopMonitoring();
    _drowsinessManager.dispose();
    _locationService.stopTracking();
    _ttsService.stop();
    _alarmPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}