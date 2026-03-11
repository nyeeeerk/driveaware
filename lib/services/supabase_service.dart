import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_state.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ─────────────────────────────────────────
  // CALIBRATION
  // ─────────────────────────────────────────

  Future<void> saveCalibration(String uid, CalibrationData data) async {
    await _client.from('calibrations').upsert({
      'user_id': uid,
      'awake_threshold': data.awakeThreshold,
      'drowsy_threshold': data.drowsyThreshold,
      'sleeping_threshold': data.sleepingThreshold,
      'yawn_threshold': data.yawnThreshold,
      'calibrated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<CalibrationData?> loadCalibration(String uid) async {
    try {
      final data = await _client
          .from('calibrations')
          .select()
          .eq('user_id', uid)
          .order('calibrated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;

      return CalibrationData(
        awakeThreshold: (data['awake_threshold'] as num).toDouble(),
        drowsyThreshold: (data['drowsy_threshold'] as num).toDouble(),
        sleepingThreshold: (data['sleeping_threshold'] as num).toDouble(),
        yawnThreshold: (data['yawn_threshold'] as num).toDouble(),
      );
    } catch (e) {
      return null;
    }
  }
}
