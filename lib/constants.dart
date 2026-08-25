import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // CONFIG
  static const String appName = "DriveAware";

  // SUPABASE
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // AI (OpenRouter)
  static String get openRouterApiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';
  static String get openRouterUrl => dotenv.env['OPENROUTER_URL'] ?? 'https://openrouter.ai/api/v1/chat/completions';
  static String get aiModel => dotenv.env['AI_MODEL'] ?? 'arcee-ai/trinity-large-preview:free';

  // ELEVENLABS TTS
  static String get elevenLabsApiKey => dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  static String get elevenLabsVoiceId => dotenv.env['ELEVENLABS_VOICE_ID'] ?? '21m00Tcm4TlvDq8ikWAM';

  // MAPBOX
  static String get mapboxToken => dotenv.env['MAPBOX_TOKEN'] ?? '';

  // DRIVER SAFETY THRESHOLDS (Advanced PERCLOS & Head Pose)
  static const int blinkDurationLongThreshold = 1500; // ms (Microsleep -> Critical)
  static const int blinkDurationSleepThreshold = 4000; // ms (True sleep -> Sleeping)
  
  static const int blinkMonitoringDurationWindow = 10000; // ms
  static const int blinkCountThresholdLow = 0;
  static const int blinkCountThresholdHigh = 8;
  static const int blinkCountThresholdMid = 3;
  static const int blinkDurationMidThreshold = 500; // ms
  
  static const double pitchDownAngleThreshold = -5.0;
  static const double pitchUpAngleThreshold = 15.0;
  static const int headTiltDurationThreshold = 5000; // ms

  // ANTI-GRAVITY / DROWSINESS DETECTION (PITCH AXIS)
  static const double pitchWarningAngleThreshold = 25.0;  // degrees downward drop from baseline
  static const int pitchWarningDurationMs = 1500;         // ms (> 1.5 seconds)
  static const double pitchCriticalAngleThreshold = 40.0; // degrees downward drop from baseline
  static const int bobbingWindowMs = 5000;                // ms (5.0 seconds window)
  static const int bobbingCountThreshold = 2;             // repeated bobbing dip threshold in window

  // HEAD POSITIONING & ALIGNMENT (YAW & ROLL AXES)
  static const double yawDistractionAngleThreshold = 35.0; // degrees turned away from road center
  static const int yawDistractionDurationMs = 2000;        // ms (> 2.0 consecutive seconds)
  static const double rollSlumpAngleThreshold = 20.0;      // degrees tilted ear-to-shoulder sideways
  static const int rollSlumpDurationMs = 1500;             // ms (> 1.5 consecutive seconds)

  // OCCLUSION / LOSS OF TRACKING
  static const int occlusionDurationThresholdMs = 1000;    // ms (> 1.0 second face undetectable)

  static const int yawnDurationWarningThreshold = 3000; // ms (must yawn for 3s+ to count)
  static const int yawningCountThreshold = 2; // (yawns within 10s window -> Warning)

  static const int scanningFps = 15;          // Throttle camera to save battery

  // NIGHT MODE (Ambient Light Detection)
  static const double nightBrightnessThreshold = 60.0;  // Y-plane avg below this = night
  static const double dayBrightnessThreshold = 90.0;    // Y-plane avg above this = day (hysteresis)

  // Warning cooldown
  static const int warningCooldown = 30; // seconds
}
