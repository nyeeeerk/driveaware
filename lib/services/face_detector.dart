import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/driver_state.dart';
import '../constants.dart';
import '../utils/ema.dart';

class DrowsinessResult {
  final double score;
  final double leftEAR;
  final double rightEAR;
  final bool eyesClosed;
  final bool isProlongedEyesClosed;
  final bool isMicrosleep;
  final bool isUnnaturalBlinks;
  final bool isHeadDropped;
  final bool isYawning;
  final double brightness; // 0-255 average Y-plane luminance

  // 1. Anti-Gravity / Drowsiness Detection (Pitch Axis)
  final bool isPitchWarning;
  final bool isPitchCritical;
  final bool isHeadBobbing;
  final double pitchAngle;

  // 2. Head Positioning & Alignment (Yaw & Roll Axes)
  final bool isYawDistracted;
  final bool isRollSlumped;
  final double yawAngle;
  final double rollAngle;

  // 3. Occlusion / Loss of Tracking
  final bool isFaceOccluded;

  DrowsinessResult({
    required this.score,
    required this.leftEAR,
    required this.rightEAR,
    required this.eyesClosed,
    required this.isProlongedEyesClosed,
    required this.isMicrosleep,
    required this.isUnnaturalBlinks,
    required this.isHeadDropped,
    required this.isYawning,
    required this.brightness,
    this.isPitchWarning = false,
    this.isPitchCritical = false,
    this.isHeadBobbing = false,
    this.pitchAngle = 0.0,
    this.isYawDistracted = false,
    this.isRollSlumped = false,
    this.yawAngle = 0.0,
    this.rollAngle = 0.0,
    this.isFaceOccluded = false,
  });

  @override
  String toString() => 'Score:${score.toStringAsFixed(2)} Lux:${brightness.toStringAsFixed(0)} MS:$isMicrosleep PS:$isProlongedEyesClosed UB:$isUnnaturalBlinks HD:$isHeadDropped PW:$isPitchWarning PC:$isPitchCritical YD:$isYawDistracted RS:$isRollSlumped FO:$isFaceOccluded YW:$isYawning';
}

class Blink {
  final DateTime start;
  DateTime? end;
  Blink(this.start);
  int get durationMs => end != null ? end!.difference(start).inMilliseconds : DateTime.now().difference(start).inMilliseconds;
}

class _BlinkTracker {
  final List<Blink> _history = [];
  Blink? _currentBlink;

  void update(bool isClosed) {
    if (isClosed && _currentBlink == null) {
      _currentBlink = Blink(DateTime.now());
      _history.add(_currentBlink!);
    } else if (!isClosed && _currentBlink != null) {
      _currentBlink!.end = DateTime.now();
      _currentBlink = null;
    }

    final cutoff = DateTime.now().subtract(const Duration(milliseconds: AppConstants.blinkMonitoringDurationWindow));
    _history.removeWhere((b) => b.end != null && b.end!.isBefore(cutoff));
  }

  bool get isMicrosleep {
    if (_currentBlink != null && _currentBlink!.durationMs >= AppConstants.blinkDurationLongThreshold) {
      return true;
    }
    return false;
  }

  bool get isProlongedEyesClosed {
    if (_currentBlink != null && _currentBlink!.durationMs >= AppConstants.blinkDurationSleepThreshold) {
      return true;
    }
    return false;
  }

  bool get isUnnaturalBlinks {
    int totalCount = _history.length;
    int midCount = _history.where((b) => b.durationMs >= AppConstants.blinkDurationMidThreshold).length;

    if (totalCount < AppConstants.blinkCountThresholdLow || totalCount > AppConstants.blinkCountThresholdHigh) {
      return true;
    }
    if (midCount >= AppConstants.blinkCountThresholdMid) {
      return true;
    }
    return false;
  }

  void reset() {
    _history.clear();
    _currentBlink = null;
  }
}

class _HeadPoseTracker {
  DateTime? _pitchExceededSince;

  void update(double pitch) {
    if (pitch < AppConstants.pitchDownAngleThreshold || pitch > AppConstants.pitchUpAngleThreshold) {
      _pitchExceededSince ??= DateTime.now();
    } else {
      _pitchExceededSince = null;
    }
  }

  bool get isHeadDropped {
    if (_pitchExceededSince == null) return false;
    return DateTime.now().difference(_pitchExceededSince!).inMilliseconds >= AppConstants.headTiltDurationThreshold;
  }

  void reset() {
    _pitchExceededSince = null;
  }
}

/// Feature 1: ANTI-GRAVITY / DROWSINESS DETECTION (PITCH AXIS)
class AntiGravityTracker {
  DateTime? _pitchWarningSince;
  bool _isDirectCritical = false;
  bool _inDip = false;
  final List<DateTime> _bobbingHistory = [];

  void update(double currentPitch, {double baselinePitch = 0.0}) {
    // Drop downward from baseline: positive pitchDrop means nodding downward
    final double pitchDrop = baselinePitch - currentPitch;
    final now = DateTime.now();

    // 1. Warning Threshold: Head pitch drops downward > 25° for > 1.5s
    if (pitchDrop > AppConstants.pitchWarningAngleThreshold) {
      _pitchWarningSince ??= now;
    } else {
      _pitchWarningSince = null;
    }

    // 2. Critical Threshold: Pitch drops downward > 40°
    _isDirectCritical = pitchDrop > AppConstants.pitchCriticalAngleThreshold;

    // 3. Critical Threshold: Rapid, repeated bobbing motions within 5-second window
    // Dip threshold: > 20°; Recovery threshold: < 10°
    if (!_inDip && pitchDrop > 20.0) {
      _inDip = true;
    } else if (_inDip && pitchDrop < 10.0) {
      _inDip = false;
      _bobbingHistory.add(now); // Registered a complete bobbing cycle
    }

    // Clean up bobbing history older than 5 seconds
    final cutoff = now.subtract(const Duration(milliseconds: AppConstants.bobbingWindowMs));
    _bobbingHistory.removeWhere((t) => t.isBefore(cutoff));
  }

  bool get isPitchWarning {
    if (_pitchWarningSince == null) return false;
    return DateTime.now().difference(_pitchWarningSince!).inMilliseconds >= AppConstants.pitchWarningDurationMs;
  }

  bool get isHeadBobbing => _bobbingHistory.length >= AppConstants.bobbingCountThreshold;

  bool get isPitchCritical => _isDirectCritical || isHeadBobbing;

  void reset() {
    _pitchWarningSince = null;
    _isDirectCritical = false;
    _inDip = false;
    _bobbingHistory.clear();
  }
}

/// Feature 2: HEAD POSITIONING & ALIGNMENT (YAW & ROLL AXES)
class HeadAlignmentTracker {
  DateTime? _yawExceededSince;
  DateTime? _rollExceededSince;

  void update(double currentYaw, double currentRoll, {double baselineYaw = 0.0, double baselineRoll = 0.0}) {
    final now = DateTime.now();

    // 1. Distraction Threshold (Yaw): Head turned left or right > 35° for > 2.0s
    final double yawOffset = (currentYaw - baselineYaw).abs();
    if (yawOffset > AppConstants.yawDistractionAngleThreshold) {
      _yawExceededSince ??= now;
    } else {
      _yawExceededSince = null;
    }

    // 2. Posture/Slump Threshold (Roll): Head tilted sideways > 20°
    final double rollOffset = (currentRoll - baselineRoll).abs();
    if (rollOffset > AppConstants.rollSlumpAngleThreshold) {
      _rollExceededSince ??= now;
    } else {
      _rollExceededSince = null;
    }
  }

  bool get isYawDistracted {
    if (_yawExceededSince == null) return false;
    return DateTime.now().difference(_yawExceededSince!).inMilliseconds >= AppConstants.yawDistractionDurationMs;
  }

  bool get isRollSlumped {
    if (_rollExceededSince == null) return false;
    return DateTime.now().difference(_rollExceededSince!).inMilliseconds >= AppConstants.rollSlumpDurationMs;
  }

  void reset() {
    _yawExceededSince = null;
    _rollExceededSince = null;
  }
}

/// Feature 3: OCCLUSION / LOSS OF TRACKING
class OcclusionTracker {
  DateTime? _faceMissingSince;

  void update(bool faceDetected) {
    final now = DateTime.now();
    if (faceDetected) {
      _faceMissingSince = null;
    } else {
      _faceMissingSince ??= now;
    }
  }

  bool get isFaceOccluded {
    if (_faceMissingSince == null) return false;
    return DateTime.now().difference(_faceMissingSince!).inMilliseconds >= AppConstants.occlusionDurationThresholdMs;
  }

  void reset() {
    _faceMissingSince = null;
  }
}

class _YawnTracker {
  final List<DateTime> _yawnHistory = [];
  DateTime? _currentYawnStart;

  void update(bool isCurrentlyYawning) {
    final now = DateTime.now();

    if (isCurrentlyYawning) {
      _currentYawnStart ??= now;
    } else {
      // Yawn finished
      if (_currentYawnStart != null && now.difference(_currentYawnStart!).inMilliseconds >= AppConstants.yawnDurationWarningThreshold) {
        // Officially count it as a full yawn because it lasted long enough
        _yawnHistory.add(now);
      }
      _currentYawnStart = null;
    }

    // Clean up history older than our rolling window
    final cutoff = now.subtract(const Duration(milliseconds: AppConstants.blinkMonitoringDurationWindow));
    _yawnHistory.removeWhere((t) => t.isBefore(cutoff));
  }

  bool get isYawningWarning {
    // If they are currently yawning for more than 3s, or if they have yawned X times in the window
    if (_currentYawnStart != null && DateTime.now().difference(_currentYawnStart!).inMilliseconds >= AppConstants.yawnDurationWarningThreshold) {
      return true;
    }
    if (_yawnHistory.length >= AppConstants.yawningCountThreshold) {
      return true;
    }
    return false;
  }

  void reset() {
    _yawnHistory.clear();
    _currentYawnStart = null;
  }
}


class FaceDetectorService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, 
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isDisposed = false;
  bool _busy = false;

  final _BlinkTracker _blinks = _BlinkTracker();
  final _HeadPoseTracker _headPose = _HeadPoseTracker();
  final AntiGravityTracker _antiGravity = AntiGravityTracker();
  final HeadAlignmentTracker _headAlignment = HeadAlignmentTracker();
  final OcclusionTracker _occlusion = OcclusionTracker();
  final _YawnTracker _yawns = _YawnTracker();
  final EMA _smoother = EMA(alpha: 0.1); // Keep for UI orb smoothness only

  Future<void> initialize() async {
    // No-op; detector is ready after construction
  }

  Future<DrowsinessResult?> detectDrowsinessDetailed(
    InputImage inputImage,
    CalibrationData calibration,
  ) async {
    if (_busy || _isDisposed) return null;
    _busy = true;

    try {
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        _occlusion.update(false);
        _busy = false;

        // If face is undetectable for > 1.0 second, return result with face occlusion flagged
        if (_occlusion.isFaceOccluded) {
          return DrowsinessResult(
            score: 0.0,
            leftEAR: 1.0,
            rightEAR: 1.0,
            eyesClosed: false,
            isProlongedEyesClosed: false,
            isMicrosleep: false,
            isUnnaturalBlinks: false,
            isHeadDropped: false,
            isYawning: false,
            brightness: 128.0,
            isFaceOccluded: true,
          );
        }
        return null;
      }

      // Face detected
      _occlusion.update(true);
      final face = faces.first;

      final double leftEAR = face.leftEyeOpenProbability ?? 0.5;
      final double rightEAR = face.rightEyeOpenProbability ?? 0.5;
      final double avgEAR = (leftEAR + rightEAR) / 2.0;

      // Determine raw visual drowsiness score based on calibration
      double rawScore = 0.0;
      
      // We interpret higher score as more drowsy (0.0 = alert, 1.0 = sleeping)
      if (avgEAR <= calibration.sleepingThreshold) {
        rawScore = 1.0;
      } else if (avgEAR <= calibration.drowsyThreshold) {
        // Map linearly between drowsy and sleeping
        double range = calibration.drowsyThreshold - calibration.sleepingThreshold;
        if (range > 0) {
          rawScore = 0.6 + 0.4 * (1.0 - ((avgEAR - calibration.sleepingThreshold) / range));
        } else {
          rawScore = 0.8;
        }
      } else {
        // Awake
        double range = calibration.awakeThreshold - calibration.drowsyThreshold;
        if (range > 0) {
          rawScore = 0.6 * (1.0 - ((avgEAR - calibration.drowsyThreshold) / range).clamp(0.0, 1.0));
        } else {
          rawScore = 0.0;
        }
      }

      // Smooth the score over time purely for UI rendering (Liquid Orb)
      final score = _smoother.update(rawScore).clamp(0.0, 1.0);
      
      // Update advanced metrics (Using dynamic calibration threshold instead of constant)
      bool isClosed = avgEAR <= calibration.sleepingThreshold;
      _blinks.update(isClosed);
      
      double pitchAngle = face.headEulerAngleX ?? 0.0;
      double yawAngle = face.headEulerAngleY ?? 0.0;
      double rollAngle = face.headEulerAngleZ ?? 0.0;

      _headPose.update(pitchAngle);
      _antiGravity.update(pitchAngle, baselinePitch: calibration.baselinePitch);
      _headAlignment.update(yawAngle, rollAngle, baselineYaw: calibration.baselineYaw, baselineRoll: calibration.baselineRoll);

      // Update MAR metrics
      double mar = 0.0;
      final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth];
      final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
      final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];
      
      if (bottomMouth != null && leftMouth != null && rightMouth != null) {
        final mouthWidth = (rightMouth.position.x - leftMouth.position.x).abs();
        final mouthCenterY = (leftMouth.position.y + rightMouth.position.y) / 2.0;
        final mouthHeight = (bottomMouth.position.y - mouthCenterY).abs();
        if (mouthWidth > 0) mar = mouthHeight / mouthWidth;
      }
      
      bool isCurrentlyYawning = mar > calibration.yawnThreshold;
      _yawns.update(isCurrentlyYawning);

      bool isPS = _blinks.isProlongedEyesClosed;
      bool isMicro = _blinks.isMicrosleep;
      bool isUnnatural = _blinks.isUnnaturalBlinks;
      bool isHD = _headPose.isHeadDropped || _antiGravity.isPitchWarning || _antiGravity.isPitchCritical;
      bool isYW = _yawns.isYawningWarning;

      // Compute ambient brightness from Y-plane
      double brightness = 128.0;
      if (inputImage.bytes != null && inputImage.metadata != null) {
        final bytes = inputImage.bytes!;
        final pixelCount = inputImage.metadata!.size.width.toInt() *
            inputImage.metadata!.size.height.toInt();
        const sampleStep = 16;
        int sum = 0;
        int sampleCount = 0;
        for (int i = 0; i < pixelCount && i < bytes.length; i += sampleStep) {
          sum += bytes[i];
          sampleCount++;
        }
        if (sampleCount > 0) brightness = sum / sampleCount;
      }

      _busy = false;

      return DrowsinessResult(
        score: score, 
        leftEAR: leftEAR, 
        rightEAR: rightEAR,
        eyesClosed: isClosed, 
        isProlongedEyesClosed: isPS,
        isMicrosleep: isMicro,
        isUnnaturalBlinks: isUnnatural,
        isHeadDropped: isHD,
        isYawning: isYW,
        brightness: brightness,
        isPitchWarning: _antiGravity.isPitchWarning,
        isPitchCritical: _antiGravity.isPitchCritical,
        isHeadBobbing: _antiGravity.isHeadBobbing,
        pitchAngle: pitchAngle,
        isYawDistracted: _headAlignment.isYawDistracted,
        isRollSlumped: _headAlignment.isRollSlumped,
        yawAngle: yawAngle,
        rollAngle: rollAngle,
        isFaceOccluded: _occlusion.isFaceOccluded,
      );
    } catch (e) {
      _busy = false;
      return null;
    }
  }

  void resetSession() { 
    _blinks.reset(); 
    _headPose.reset();
    _antiGravity.reset();
    _headAlignment.reset();
    _occlusion.reset();
    _yawns.reset();
  }

  void dispose() {
    _isDisposed = true;
    _detector.close();
  }
}