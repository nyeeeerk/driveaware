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
  });

  @override
  String toString() => 'Score:${score.toStringAsFixed(2)} Lux:${brightness.toStringAsFixed(0)} MS:$isMicrosleep PS:$isProlongedEyesClosed UB:$isUnnaturalBlinks HD:$isHeadDropped YW:$isYawning';
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
        _busy = false; 
        return null; 
      }
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
      
      if (face.headEulerAngleX != null) {
        _headPose.update(face.headEulerAngleX!);
      }

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
      bool isHD = _headPose.isHeadDropped;
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
      );
    } catch (e) {
      _busy = false;
      return null;
    }
  }

  void resetSession() { 
    _blinks.reset(); 
    _headPose.reset();
    _yawns.reset();
  }

  void dispose() {
    _isDisposed = true;
    _detector.close();
  }
}