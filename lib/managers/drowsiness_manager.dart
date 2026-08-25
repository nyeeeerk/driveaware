import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/camera_service.dart';
import '../services/face_detector.dart';
import '../models/driver_state.dart';
import '../constants.dart';

class DrowsinessManager {
  // Dependencies
  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceService = FaceDetectorService();

  // Callbacks
  final Function(DriverStatus status) onStatusChanged;
  final Function(DrowsinessResult result)? onResultUpdated;
  final Function(bool isNightMode)? onNightModeChanged;

  // Internal State
  bool _isMonitoring = false;
  bool _isAnalyzing  = false;
  DriverStatus _currentStatus = DriverStatus.normal;
  DateTime? _monitoringStartTime;
  
  // Night Mode
  bool _isNightMode = false;
  double _smoothedBrightness = 128.0;
  bool _brightnessInitialized = false;

  // Internals
  final CalibrationData calibration;

  bool get isNightMode => _isNightMode;

  DrowsinessManager({
    required this.calibration,
    required this.onStatusChanged,
    this.onResultUpdated,
    this.onNightModeChanged,
  });

  // ─────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────

  Future<void> init() async {
    await _cameraService.initialize();
    await _faceService.initialize();
  }

  // ─────────────────────────────────────────
  // GETTERS
  // ─────────────────────────────────────────

  bool get isMonitoring => _isMonitoring;

  // ─────────────────────────────────────────
  // START
  // ─────────────────────────────────────────

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _currentStatus = DriverStatus.normal;
    _monitoringStartTime = DateTime.now();
    _faceService.resetSession(); 

    _cameraService.startStream((inputImage) async {
      if (!_isMonitoring || _isAnalyzing) return;
      _isAnalyzing = true;

      try {
        final result = await _faceService.detectDrowsinessDetailed(
          inputImage, calibration,
        );

        if (result != null) {
          // Update ambient light mode
          _updateNightMode(result.brightness);

          // Send full result to UI if callback provided
          onResultUpdated?.call(result);

          // Map detection flags → DriverStatus
          _processResult(result);
        }
      } catch (e) {
        debugPrint("Detection Error: $e");
      } finally {
        _isAnalyzing = false;
      }
    });
  }

  // ─────────────────────────────────────────
  // STOP
  // ─────────────────────────────────────────

  void stopMonitoring() {
    _isMonitoring  = false;
    _isAnalyzing   = false;
    _currentStatus = DriverStatus.normal;
    _faceService.resetSession();
    _cameraService.stopStream(); 
  }

  // ─────────────────────────────────────────
  // CORE LOGIC
  // Maps detection flags → DriverStatus
  // ─────────────────────────────────────────

  void _processResult(DrowsinessResult result) {
    // Grace period: ignore alerts for first 5 seconds
    if (_monitoringStartTime != null &&
        DateTime.now().difference(_monitoringStartTime!).inSeconds < 5) {
      debugPrint('📊 ${result.toString()} (warm-up)');
      return;
    }

    DriverStatus newStatus;

    // Model score is logged but NOT used for escalation until tuned

    if (result.isPitchCritical || result.isProlongedEyesClosed) {
      newStatus = DriverStatus.sleeping;
    } else if (result.isMicrosleep || result.isPitchWarning) {
      newStatus = DriverStatus.critical;
    } else if (result.isYawDistracted || result.isRollSlumped || result.isFaceOccluded || result.isUnnaturalBlinks || result.isYawning || result.isHeadDropped) {
      newStatus = DriverStatus.warning;
    } else {
      newStatus = DriverStatus.normal;
    }

    debugPrint('📊 ${result.toString()}');
    _updateStatus(newStatus);
  }

  void _updateNightMode(double brightness) {
    // EMA smooth brightness to prevent flickering
    if (!_brightnessInitialized) {
      _smoothedBrightness = brightness;
      _brightnessInitialized = true;
    } else {
      _smoothedBrightness = 0.1 * brightness + 0.9 * _smoothedBrightness;
    }

    // Hysteresis: use two different thresholds for entering/exiting night mode
    if (!_isNightMode && _smoothedBrightness < AppConstants.nightBrightnessThreshold) {
      _isNightMode = true;
      debugPrint('🌙 NIGHT MODE activated (brightness: ${_smoothedBrightness.toStringAsFixed(1)})');
      onNightModeChanged?.call(true);
    } else if (_isNightMode && _smoothedBrightness > AppConstants.dayBrightnessThreshold) {
      // Auto-switch back only if brightness clearly returns to day levels
      _isNightMode = false;
      debugPrint('☀️ DAY MODE restored (brightness: ${_smoothedBrightness.toStringAsFixed(1)})');
      onNightModeChanged?.call(false);
    }
  }

  /// Manual toggle for night mode override
  void setNightMode(bool enabled) {
    if (_isNightMode == enabled) return;
    _isNightMode = enabled;
    debugPrint(enabled ? '🌙 NIGHT MODE manually enabled' : '☀️ DAY MODE manually enabled');
    onNightModeChanged?.call(enabled);
  }

  void _updateStatus(DriverStatus newStatus) {
    if (_currentStatus != newStatus ||
        newStatus == DriverStatus.sleeping ||
        newStatus == DriverStatus.critical) {
      _currentStatus = newStatus;
      onStatusChanged(newStatus);
    }
  }

  // ─────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────

  void dispose() {
    _cameraService.stop();
    _faceService.dispose();
  }
}