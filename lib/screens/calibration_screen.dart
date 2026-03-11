import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'dart:async';

import '../services/camera_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../models/driver_state.dart';
import 'active_monitoring_screen.dart';

enum CalibrationStage { intro, calibrating, complete }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> with TickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true, // Need landmarks for MAR
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  CalibrationStage _stage = CalibrationStage.intro;
  bool _isInitializing = false;
  
  // Data collection
  final List<double> _awakeEARs = [];
  final List<double> _awakeMARs = []; // Store baseline relaxed mouth ratios
  
  double _progress = 0.0;
  Timer? _calibrationTimer;
  bool _isDetecting = false;
  bool _isAdvancing = false;

  // Animation & Countdown for Complete Stage
  Timer? _countdownTimer;
  int _countdown = 3;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _progressController;
  CalibrationData? _calibrationResult;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _progressController = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _calibrationTimer?.cancel();
    _countdownTimer?.cancel();
    if (!_isAdvancing) {
      _cameraService.stop();
    }
    _detector.close();
    _fadeController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    setState(() => _isInitializing = true);
    await _cameraService.initialize(
      onInitialized: () {
        if (mounted) setState(() {});
      }
    );
    
    _cameraService.startStream((inputImage) async {
      if (_isDetecting || _stage != CalibrationStage.calibrating) return;
      _isDetecting = true;
      try {
        final faces = await _detector.processImage(inputImage);
        if (faces.isNotEmpty) {
          final face = faces.first;
          final leftEAR = face.leftEyeOpenProbability ?? 0.5;
          final rightEAR = face.rightEyeOpenProbability ?? 0.5;
          final avgEAR = (leftEAR + rightEAR) / 2.0;
          
          // Calculate MAR (Mouth Aspect Ratio) using landmarks
          double mar = 0.0;
          final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth];
          final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
          final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];
          
          if (bottomMouth != null && leftMouth != null && rightMouth != null) {
            // Rough approximation of mouth vertical vs horizontal opening
            // Ideally we also need topMouth, but bottom to line-between-corners works as an open-proxy
            final mouthWidth = (rightMouth.position.x - leftMouth.position.x).abs();
            // Estimate center 'closed' mouth Y position from corners
            final mouthCenterY = (leftMouth.position.y + rightMouth.position.y) / 2.0;
            final mouthHeight = (bottomMouth.position.y - mouthCenterY).abs();
            
            if (mouthWidth > 0) {
              mar = mouthHeight / mouthWidth;
            }
          }

          if (mounted && _stage == CalibrationStage.calibrating) {
            _awakeEARs.add(avgEAR);
            if (mar > 0) _awakeMARs.add(mar);
          }
        }
      } catch (e) {
        // Handle error implicitly
      } finally {
        _isDetecting = false;
      }
    });
    
    setState(() {
      _isInitializing = false;
      _stage = CalibrationStage.calibrating;
    });
    
    _startRecordingState();
  }

  void _startRecordingState() {
    setState(() => _progress = 0.0);
    // Needs 5 seconds of good data. If face isn't detected, it won't add to list, 
    // but we'll cap the timer to 5s anyway for UX.
    const totalTimeMs = 5000;
    const intervalMs = 100;
    
    _calibrationTimer?.cancel();
    _calibrationTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _progress = (timer.tick * intervalMs) / totalTimeMs;
      });
      
      if (timer.tick * intervalMs >= totalTimeMs) {
        timer.cancel();
        _finishCalibration();
      }
    });
  }

  void _finishCalibration() {
    setState(() => _stage = CalibrationStage.complete);
    _cameraService.stopStream();

    // Calculate a clean EAR baseline: 
    // Sort and take the top 50% of readings to eliminate blinks
    double awakeAverage = 0.9;
    if (_awakeEARs.isNotEmpty) {
      _awakeEARs.sort();
      final startIndex = _awakeEARs.length ~/ 2; 
      final topHalf = _awakeEARs.sublist(startIndex);
      awakeAverage = topHalf.reduce((a, b) => a + b) / topHalf.length;
    }

    // Calculate a clean MAR baseline:
    // Sort and take the top 50% of readings to eliminate tight mouths
    double awakeMAR = 0.1;
    if (_awakeMARs.isNotEmpty) {
      _awakeMARs.sort();
      final startIndex = _awakeMARs.length ~/ 2;
      final topHalf = _awakeMARs.sublist(startIndex);
      awakeMAR = topHalf.reduce((a, b) => a + b) / topHalf.length;
    }

    // Lowered the clamp from 0.6 to 0.35 to support narrower eye shapes
    final safeAwake = awakeAverage.clamp(0.35, 1.0);
    final safeDrowsy = (safeAwake * 0.75).clamp(0.2, safeAwake - 0.1);
    final safeSleeping = (safeAwake * 0.35).clamp(0.0, safeDrowsy - 0.1);
    
    // Yawn threshold: 2.5x baseline, with a wider dynamic range
    final safeYawn = (awakeMAR * 2.5).clamp(0.2, 1.5);

    _calibrationResult = CalibrationData(
      awakeThreshold: safeAwake,
      drowsyThreshold: safeDrowsy,
      sleepingThreshold: safeSleeping,
      yawnThreshold: safeYawn,
    );

    // Save calibration to Firestore
    final uid = _authService.uid;
    if (uid != null && _calibrationResult != null) {
      _supabaseService.saveCalibration(uid, _calibrationResult!);
    }

    _fadeController.forward();
    _progressController.forward();
    
    _countdown = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          timer.cancel();
          _navigateToMonitoring();
        }
      });
    });
  }

  void _navigateToMonitoring() {
    if (_isAdvancing || _calibrationResult == null) return;
    _isAdvancing = true;
    _countdownTimer?.cancel();
    
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ActiveMonitoringScreen(calibration: _calibrationResult!),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == CalibrationStage.complete) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: _buildCompleteScreen(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.5,
                  colors: [
                    const Color(0xFF13EC5B).withOpacity(0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCameraPreview(),
                  const SizedBox(height: 48),
                  Text(
                    _getTitle(),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _getDescription(),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  
                  if (_stage == CalibrationStage.intro)
                    _isInitializing
                        ? const CircularProgressIndicator(color: Color(0xFF13EC5B))
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF13EC5B),
                              foregroundColor: const Color(0xFF121212),
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _startCamera,
                            child: const Text('Start Calibration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          )
                  else if (_stage == CalibrationStage.calibrating) ...[
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF13EC5B)),
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 16),
                    Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteScreen() {
    return Stack(
      children: [
        // Glow background
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  const Color(0xFF13EC5B).withOpacity(0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Spacer(),
                
                // Center Orb and Text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animation Stack
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Progress ring
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, child) {
                                return CircularProgressIndicator(
                                  value: _progressController.value,
                                  strokeWidth: 2,
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF13EC5B)),
                                );
                              }
                            ),
                          ),
                          // Pulse ring
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final scale = 1.0 + (_pulseController.value * 0.2);
                              final opacity = 0.4 - (_pulseController.value * 0.3);
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF13EC5B).withOpacity(opacity.clamp(0.0, 1.0)),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              );
                            }
                          ),
                          // Inner Orb
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                center: Alignment(-0.3, -0.3),
                                colors: [
                                  Color(0xFF4AFF8D),
                                  Color(0xFF13EC5B),
                                  Color(0xFF0C9E3C),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF13EC5B).withOpacity(0.4),
                                  blurRadius: 40,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Text Fade in
                    FadeTransition(
                      opacity: _fadeController,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _fadeController,
                          curve: Curves.easeOut,
                        )),
                        child: Column(
                          children: [
                            const Text(
                              "Calibration\nSuccessful",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "Your Guardian AI is now active.",
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _countdown > 0 
                                  ? "Starting monitoring in ${_countdown}s..."
                                  : "Starting monitoring now...",
                              style: TextStyle(
                                color: const Color(0xFF13EC5B).withOpacity(0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Bottom Buttons Fade In (delayed)
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fadeController,
                    curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.5),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _fadeController,
                      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
                    )),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "DRIVE SAFELY.",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _navigateToMonitoring,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: const Color(0xFF13EC5B).withOpacity(0.3), width: 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: Colors.white.withOpacity(0.05),
                              foregroundColor: const Color(0xFF13EC5B),
                            ),
                            child: const Text(
                              "Got it",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF13EC5B).withOpacity(0.5), width: 4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13EC5B).withOpacity(0.15),
            blurRadius: 40,
            spreadRadius: 10,
          )
        ],
      ),
      child: ClipOval(
        child: _cameraService.controller != null && _cameraService.controller!.value.isInitialized
            ? AspectRatio(
                aspectRatio: 1, // Force square/circle crop
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraService.controller!.value.previewSize?.height ?? 1,
                    height: _cameraService.controller!.value.previewSize?.width ?? 1,
                    child: CameraPreview(_cameraService.controller!),
                  ),
                ),
              )
            : Container(
                color: Colors.white.withOpacity(0.05),
                child: const Icon(Icons.face_retouching_natural, size: 80, color: Color(0xFF13EC5B)),
              ),
      ),
    );
  }

  String _getTitle() {
    switch (_stage) {
      case CalibrationStage.intro: return "Face Analysis";
      case CalibrationStage.calibrating: return "Calibrating...";
      case CalibrationStage.complete: return "Calibration Complete";
    }
  }

  String _getDescription() {
    switch (_stage) {
      case CalibrationStage.intro: return "Ensure your face is clearly visible. When ready, stare straight into the camera.";
      case CalibrationStage.calibrating: return "Look straight at the camera with your eyes fully open as if you were driving. Keep your head still.";
      case CalibrationStage.complete: return "Your drowsiness thresholds have been dynamically generated. Starting journey...";
    }
  }
}
