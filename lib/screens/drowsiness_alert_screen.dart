import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import '../controllers/monitoring_controller.dart';
import '../models/driver_state.dart';

class DrowsinessAlertScreen extends StatefulWidget {
  final MonitoringController controller;
  final Duration timeoutDuration;

  const DrowsinessAlertScreen({
    super.key, 
    required this.controller,
    this.timeoutDuration = const Duration(seconds: 15),
  });

  @override
  State<DrowsinessAlertScreen> createState() => _DrowsinessAlertScreenState();
}

class _DrowsinessAlertScreenState extends State<DrowsinessAlertScreen> with TickerProviderStateMixin {
  late Timer _autoDismissTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    
    _autoDismissTimer = Timer(widget.timeoutDuration, _handleTimeout);

    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _waveController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() {
    _autoDismissTimer.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _handleTimeout() {
    // Don't auto-dismiss during sleeping (alarm must be manually stopped)
    if (widget.controller.status == DriverStatus.sleeping) return;
    if (widget.controller.isAlarmPlaying) return;
    if (mounted) Navigator.pop(context);
  }

  void _onFindCoffeeTap() {
    _autoDismissTimer.cancel();
    widget.controller.findCoffeeAction();
    Navigator.pop(context); 
  }

  void _onImAwakeTap() {
    _autoDismissTimer.cancel();
    widget.controller.stopAlarm();
    Navigator.pop(context); 
  }

  void _onRespondTap() {
    widget.controller.stopAlarm();
    widget.controller.startListening();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101922),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          final status = widget.controller.status;
          final aiMessage = widget.controller.message;
          final alertColor = _getAlertColor(status);

          return Stack(
            children: [
              _buildAmbientGlows(alertColor),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTopSection(alertColor, aiMessage),
                      _buildMiddleSection(alertColor, status),
                      _buildBottomSection(alertColor),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getAlertColor(DriverStatus status) {
    switch (status) {
      case DriverStatus.normal: return const Color(0xFF137FEC); // Blue
      case DriverStatus.warning: return const Color(0xFFF59E0B); // Amber/Orange
      case DriverStatus.critical: return const Color(0xFFE11D48); // Red
      case DriverStatus.sleeping: return const Color(0xFFDC2626); // Dark Red
      default: return const Color(0xFF137FEC);
    }
  }

  Widget _buildAmbientGlows(Color color) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: -100,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseAnimation.value * 0.05),
                child: Opacity(
                  opacity: _pulseAnimation.value,
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.2),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 100, spreadRadius: 50)],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          bottom: -50,
          right: -50,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
              boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 80, spreadRadius: 40)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopSection(Color color, String aiMessage) {
    return Column(
      children: [
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text("DROWSINESS DETECTED", style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.4), 
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF9333EA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("AI ASSISTANT", style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                            _buildWaveform(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(aiMessage, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w500, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWaveBar(0.0), _buildWaveBar(0.5), _buildWaveBar(1.0), _buildWaveBar(1.5), _buildWaveBar(2.0),
        ],
      ),
    );
  }

  Widget _buildWaveBar(double offset) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        final height = 6.0 + 10.0 * (math.sin((_waveController.value * 2 * math.pi) + offset).abs());
        final color = _getAlertColor(widget.controller.status).withOpacity(0.8);
        return Container(
          width: 3,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        );
      },
    );
  }

  Widget _buildMiddleSection(Color color, DriverStatus status) {
    String title1 = "Time for\n";
    String title2 = "a break?";
    String subtitle = "Staying alert keeps you safe.\nLet's take a moment.";
    
    if (status == DriverStatus.critical) {
      title1 = "Critical\n";
      title2 = "Fatigue";
      subtitle = "Please pull over immediately.\nContinuous driving is unsafe.";
    } else if (status == DriverStatus.sleeping) {
      title1 = "WAKE\n";
      title2 = "UP!";
      subtitle = "DRIVER UNRESPONSIVE.\nPULL OVER NOW.";
    } else if (status == DriverStatus.normal) {
      title1 = "System\n";
      title2 = "Active";
      subtitle = "Driver recovered.\nKeep your eyes on the road.";
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(child: Icon(Icons.bedtime_outlined, size: 180, color: color.withOpacity(0.1))),
        Column(
          children: [
            Text(title1, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 0.5)),
            Text(title2, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 48, fontWeight: FontWeight.w800, height: 1.0)),
            const SizedBox(height: 24),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 18, height: 1.5)),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomSection(Color color) {
    final isSleeping = widget.controller.status == DriverStatus.sleeping || widget.controller.isAlarmPlaying;
    
    return Column(
      children: [
        // Respond button (mic) - shown during sleeping alerts
        if (isSleeping || widget.controller.isListening)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.controller.isListening 
                      ? const Color(0xFF22C55E) 
                      : const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _onRespondTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.controller.isListening ? Icons.mic : Icons.mic_none, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      widget.controller.isListening ? "Listening..." : "Respond",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 40, spreadRadius: -10)],
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1)),
              elevation: 0,
            ),
            onPressed: _onFindCoffeeTap,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_cafe, size: 28),
                SizedBox(width: 12),
                Text("Find Coffee", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B).withOpacity(0.5), 
              foregroundColor: const Color(0xFFE2E8F0), 
              side: BorderSide(color: const Color(0xFF334155).withOpacity(0.5), width: 1), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _onImAwakeTap,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility, color: Color(0xFF137FEC), size: 28), 
                SizedBox(width: 12),
                Text("I'm awake", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}