enum DriverStatus {
  normal,   // Eyes open, attentive
  warning,  // Excessive blinking or minor distraction
  critical, // Eyes closed for X seconds
  sleeping  // No response (escalation)
}

class CalibrationData {
  final double awakeThreshold;
  final double drowsyThreshold;
  final double sleepingThreshold;
  final double yawnThreshold;
  final double baselinePitch;
  final double baselineYaw;
  final double baselineRoll;

  const CalibrationData({
    required this.awakeThreshold,
    required this.drowsyThreshold,
    required this.sleepingThreshold,
    required this.yawnThreshold,
    this.baselinePitch = 0.0,
    this.baselineYaw = 0.0,
    this.baselineRoll = 0.0,
  });

  bool get isCalibrated =>
      awakeThreshold > 0 && drowsyThreshold > 0 && sleepingThreshold > 0 && yawnThreshold > 0;

  @override
  String toString() =>
      'CalibrationData(awake: ${awakeThreshold.toStringAsFixed(2)}, drowsy: ${drowsyThreshold.toStringAsFixed(2)}, sleeping: ${sleepingThreshold.toStringAsFixed(2)}, yawn: ${yawnThreshold.toStringAsFixed(2)}, pitch: ${baselinePitch.toStringAsFixed(1)}, yaw: ${baselineYaw.toStringAsFixed(1)}, roll: ${baselineRoll.toStringAsFixed(1)})';
}