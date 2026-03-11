import 'package:flutter/material.dart';
import 'dart:ui';

import '../controllers/monitoring_controller.dart';
import '../models/driver_state.dart';
import '../providers/theme_provider.dart';
import 'drowsiness_alert_screen.dart';

class ActiveMonitoringScreen extends StatefulWidget {
  final CalibrationData calibration;

  const ActiveMonitoringScreen({
    super.key,
    required this.calibration,
  });

  @override
  State<ActiveMonitoringScreen> createState() => _ActiveMonitoringScreenState();
}

class _ActiveMonitoringScreenState extends State<ActiveMonitoringScreen> with TickerProviderStateMixin {
  late final MonitoringController _controller;
  bool _isAlertShowing = false;

  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  
  // NEW: Liquid Effect Variables
  late AnimationController _liquidController;
  late Animation<BorderRadius?> _liquidAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _controller = MonitoringController(
      calibration: widget.calibration,
      onRequireAlertPopup: _showDrowsinessAlert,
    );
  }

  void _showDrowsinessAlert() async {
    if (_isAlertShowing) return;
    _isAlertShowing = true;
    
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => DrowsinessAlertScreen(
          // Since we are using your exact code, we leave this as you had it
          // Note: ensure DrowsinessAlertScreen accepts the controller if you pass it!
           controller: _controller, 
          timeoutDuration: const Duration(seconds: 15), 
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.0, 0.1), end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
    
    _isAlertShowing = false;
  }

  void _setupAnimations() {
    _breatheController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _breatheAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut));
    
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: 0, end: -10).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));

    // NEW: Liquid Animation setup mimicking the CSS border-radius percentages
    _liquidController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _liquidAnimation = BorderRadiusTween(
      begin: BorderRadius.only(
        topLeft: const Radius.elliptical(200 * 0.6, 200 * 0.6),
        topRight: const Radius.elliptical(200 * 0.4, 200 * 0.3),
        bottomRight: const Radius.elliptical(200 * 0.3, 200 * 0.7),
        bottomLeft: const Radius.elliptical(200 * 0.7, 200 * 0.4),
      ),
      end: BorderRadius.only(
        topLeft: const Radius.elliptical(200 * 0.3, 200 * 0.5),
        topRight: const Radius.elliptical(200 * 0.6, 200 * 0.6),
        bottomRight: const Radius.elliptical(200 * 0.7, 200 * 0.3),
        bottomLeft: const Radius.elliptical(200 * 0.4, 200 * 0.6),
      ),
    ).animate(CurvedAnimation(parent: _liquidController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    _liquidController.dispose(); // NEW: Dispose the liquid controller
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final theme = AppTheme.of(_controller.isNightMode);
        return Scaffold(
          backgroundColor: theme.background,
          body: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.backgroundGradientStart, theme.backgroundGradientMid, theme.backgroundGradientEnd],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(child: _buildCentralDisplay()),
                    _buildControlPanel(),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: const Icon(Icons.shield_outlined, color: Color(0xFFC7D2FE), size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "ACTIVE MONITORING",
                style: TextStyle(
                  color: _controller.isNightMode ? const Color(0xFFE0E7FF).withOpacity(0.8) : const Color(0xFF334155), 
                  fontSize: 14, 
                  fontWeight: FontWeight.w600, 
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          // Manual toggle badge
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _controller.toggleNightMode,
                borderRadius: BorderRadius.circular(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _controller.isNightMode 
                            ? const Color(0xFF6366F1).withOpacity(0.15)
                            : const Color(0xFFFACC15).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _controller.isNightMode 
                              ? const Color(0xFF818CF8).withOpacity(0.3)
                              : const Color(0xFFEAB308).withOpacity(0.4)
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(_controller.isNightMode ? "\u{1F319}" : "\u{2600}\u{FE0F}", style: const TextStyle(fontSize: 10)),
                          const SizedBox(width: 4),
                          Text(
                            _controller.isNightMode ? "NIGHT" : "DAY", 
                            style: TextStyle(
                              color: _controller.isNightMode ? const Color(0xFFC4B5FD) : const Color(0xFFB45309), 
                              fontSize: 12, 
                              fontWeight: FontWeight.bold, 
                              letterSpacing: 0.5
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _controller.isNightMode ? const Color(0xFF22C55E).withOpacity(0.1) : const Color(0xFF16A34A).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _controller.isNightMode ? const Color(0xFF22C55E).withOpacity(0.2) : const Color(0xFF16A34A).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _pulseAnimation.value,
                          child: Container(
                            width: 6, 
                            height: 6, 
                            decoration: BoxDecoration(
                              color: _controller.isNightMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D), 
                              shape: BoxShape.circle
                            )
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "LIVE", 
                      style: TextStyle(
                        color: _controller.isNightMode ? const Color(0xFF86EFAC) : const Color(0xFF166534), 
                        fontSize: 12, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: 0.5
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCentralDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // NEW: Replaced the static circle with the animated Liquid Orb
              AnimatedBuilder(
                animation: Listenable.merge([_breatheController, _liquidController]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: _breatheAnimation.value,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: _liquidAnimation.value, // Morphing shape
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.4),
                          radius: 0.8,
                          colors: _controller.isNightMode
                            ? [const Color(0xFFA5B4FC).withOpacity(0.8), const Color(0xFF6366F1).withOpacity(0.4), const Color(0xFF4F46E5).withOpacity(0.1)]
                            : [const Color(0xFF38BDF8).withOpacity(0.9), const Color(0xFF3B82F6).withOpacity(0.5), const Color(0xFF2563EB).withOpacity(0.2)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _controller.isNightMode 
                                ? const Color(0xFF6366F1).withOpacity(0.3)
                                : const Color(0xFF0EA5E9).withOpacity(0.4), 
                            blurRadius: 60, 
                            spreadRadius: 10
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: _liquidAnimation.value ?? BorderRadius.circular(100), // Ensures blur stays inside morphing shape
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), 
                          child: Container(color: Colors.transparent)
                        ),
                      ),
                    ),
                  );
                },
              ),

              AnimatedBuilder(
                animation: _floatController,
                builder: (context, child) {
                  return Transform.translate(offset: Offset(0, _floatAnimation.value), child: child);
                },
                child: const Icon(Icons.graphic_eq, size: 60, color: Colors.white, shadows: [Shadow(color: Color(0x80FFFFFF), blurRadius: 15)]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Text(
            _controller.isListening ? "Listening..." : _controller.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _controller.isNightMode ? Colors.white : const Color(0xFF1E293B),
              fontSize: 24,
              fontWeight: FontWeight.w300,
              height: 1.5,
              shadows: _controller.isNightMode 
                  ? const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                  : [],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 4,
          width: 64,
          decoration: BoxDecoration(color: const Color(0xFF818CF8).withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Padding(
      padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 40.0, top: 16.0),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.stop_circle_outlined, color: Color(0xFFFECACA), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text("End Journey", style: TextStyle(color: Color(0xFFFEE2E2), fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSecondaryAction(
                  icon: _controller.isListening ? Icons.mic_off : Icons.mic,
                  label: "Voice Command",
                  color: const Color(0xFF6366F1),
                  onTap: _controller.startListening,
                  isActive: _controller.isListening,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSecondaryAction(
                  icon: _controller.isNightMode ? Icons.wb_sunny : Icons.nightlight_round,
                  label: _controller.isNightMode ? "Day Mode" : "Night Mode",
                  color: _controller.isNightMode ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
                  onTap: _controller.toggleNightMode,
                  isActive: _controller.isNightMode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryAction({required IconData icon, required String label, required Color color, required VoidCallback onTap, bool isActive = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: isActive 
                ? (_controller.isNightMode ? color.withOpacity(0.2) : color.withOpacity(0.15))
                : (_controller.isNightMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive 
                  ? (_controller.isNightMode ? color.withOpacity(0.5) : color.withOpacity(0.4))
                  : (_controller.isNightMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1))
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: isActive ? color.withOpacity(0.5) : color.withOpacity(0.2), shape: BoxShape.circle),
                    child: Icon(icon, color: isActive ? Colors.white : color.withOpacity(0.8), size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label, 
                    style: TextStyle(
                      color: _controller.isNightMode ? const Color(0xFFE0E7FF) : const Color(0xFF334155), 
                      fontSize: 14, 
                      fontWeight: FontWeight.w500
                    )
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}