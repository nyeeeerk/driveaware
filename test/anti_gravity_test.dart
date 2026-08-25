import 'package:flutter_test/flutter_test.dart';
import 'package:drive_aware/services/face_detector.dart';

void main() {
  group('Feature 1: Anti-Gravity / Drowsiness Detection (Pitch Axis)', () {
    late AntiGravityTracker tracker;

    setUp(() {
      tracker = AntiGravityTracker();
    });

    test('Warning Threshold: Pitch drop > 25 degrees for > 1.5 seconds', () async {
      expect(tracker.isPitchWarning, isFalse);

      // Pitch drops downward by 30° (currentPitch = -30.0 with baseline 0.0)
      tracker.update(-30.0, baselinePitch: 0.0);
      expect(tracker.isPitchWarning, isFalse); // Not yet 1.5s

      // Wait 1.6 seconds to exceed duration threshold
      await Future.delayed(const Duration(milliseconds: 1600));
      tracker.update(-30.0, baselinePitch: 0.0);
      expect(tracker.isPitchWarning, isTrue);

      // Recover pitch back to baseline
      tracker.update(0.0, baselinePitch: 0.0);
      expect(tracker.isPitchWarning, isFalse);
    });

    test('Critical Threshold: Pitch drop > 40 degrees', () {
      expect(tracker.isPitchCritical, isFalse);

      // Pitch drops downward by 45°
      tracker.update(-45.0, baselinePitch: 0.0);
      expect(tracker.isPitchCritical, isTrue);
    });

    test('Critical Threshold: Rapid, repeated bobbing motions within 5 seconds', () async {
      expect(tracker.isHeadBobbing, isFalse);

      // First dip (> 20°) & recovery (< 10°)
      tracker.update(-25.0, baselinePitch: 0.0);
      tracker.update(0.0, baselinePitch: 0.0);

      // Second dip (> 20°) & recovery (< 10°) within 5s
      tracker.update(-25.0, baselinePitch: 0.0);
      tracker.update(0.0, baselinePitch: 0.0);

      expect(tracker.isHeadBobbing, isTrue);
      expect(tracker.isPitchCritical, isTrue);
    });
  });

  group('Feature 2: Head Positioning & Alignment (Yaw & Roll Axes)', () {
    late HeadAlignmentTracker tracker;

    setUp(() {
      tracker = HeadAlignmentTracker();
    });

    test('Distraction Threshold (Yaw): Turned > 35 degrees for > 2.0 seconds', () async {
      expect(tracker.isYawDistracted, isFalse);

      // Yaw turned 40° right
      tracker.update(40.0, 0.0, baselineYaw: 0.0, baselineRoll: 0.0);
      expect(tracker.isYawDistracted, isFalse); // Not yet 2.0s

      // Wait 2.1 seconds
      await Future.delayed(const Duration(milliseconds: 2100));
      tracker.update(40.0, 0.0, baselineYaw: 0.0, baselineRoll: 0.0);
      expect(tracker.isYawDistracted, isTrue);

      // Re-center head
      tracker.update(0.0, 0.0, baselineYaw: 0.0, baselineRoll: 0.0);
      expect(tracker.isYawDistracted, isFalse);
    });

    test('Posture/Slump Threshold (Roll): Tilted sideways > 20 degrees', () async {
      expect(tracker.isRollSlumped, isFalse);

      // Roll tilted 25°
      tracker.update(0.0, 25.0, baselineYaw: 0.0, baselineRoll: 0.0);
      expect(tracker.isRollSlumped, isFalse);

      // Wait 1.6 seconds
      await Future.delayed(const Duration(milliseconds: 1600));
      tracker.update(0.0, 25.0, baselineYaw: 0.0, baselineRoll: 0.0);
      expect(tracker.isRollSlumped, isTrue);
    });
  });

  group('Feature 3: Occlusion / Loss of Tracking', () {
    late OcclusionTracker tracker;

    setUp(() {
      tracker = OcclusionTracker();
    });

    test('Threshold: Face undetectable for > 1.0 second', () async {
      expect(tracker.isFaceOccluded, isFalse);

      // Face missing
      tracker.update(false);
      expect(tracker.isFaceOccluded, isFalse); // Not yet 1.0s

      // Wait 1.1 seconds
      await Future.delayed(const Duration(milliseconds: 1100));
      tracker.update(false);
      expect(tracker.isFaceOccluded, isTrue);

      // Face re-detected
      tracker.update(true);
      expect(tracker.isFaceOccluded, isFalse);
    });
  });
}
