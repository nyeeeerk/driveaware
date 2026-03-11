import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';

import 'calibration_screen.dart';
import 'active_monitoring_screen.dart';
import 'login_screen.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../models/driver_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  
  // Blink Controllers
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  String _userName = 'Driver';
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();

    // Floating Animation
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: 0, end: -15).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));

    // Blinking Animation
    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.05).animate(CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut));
    
    _startRandomBlinking();
    _loadUserName();

    // Request location permissions as soon as the app starts
    LocationService().requestPermission().then((_) {
      LocationService().startTracking();
    });
  }

  Future<void> _loadUserName() async {
    final name = await _authService.getUserName();
    if (mounted) setState(() => _userName = name);
  }

  // Loop to trigger blinks at random intervals
  void _startRandomBlinking() async {
    final random = Random();
    while (mounted) {
      // Wait between 1.5 and 4.5 seconds
      int delay = 1500 + random.nextInt(3000);
      await Future.delayed(Duration(milliseconds: delay));
      
      if (mounted) {
        await _blinkController.forward(); // Close eye
        await _blinkController.reverse(); // Open eye
      }
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _startJourney() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      final uid = _authService.uid;
      CalibrationData? saved;
      if (uid != null) {
        saved = await _supabaseService.loadCalibration(uid);
      }

      if (!mounted) return;

      if (saved != null && saved.isCalibrated) {
        // Saved calibration found — skip straight to monitoring
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => ActiveMonitoringScreen(calibration: saved!),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else {
        // No calibration — go through calibration flow
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const CalibrationScreen(),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      debugPrint('Start journey error: $e');
      // Fallback: go to calibration
      if (mounted) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const CalibrationScreen(),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _recalibrate() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const CalibrationScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1021),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.6, 1.0],
                colors: [Color(0xFF1E1B2E), Color(0xFF0B1021), Color(0xFF050810)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          _buildGreeting(),
                          const SizedBox(height: 40),
                          _buildBlinkingEye(), // Replaced _buildAnimatedOrb
                          const SizedBox(height: 40),
                          _buildDescription(),
                          const SizedBox(height: 40),
                          _buildStartButton(),
                          const SizedBox(height: 24),
                          _buildSecondaryActions(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.menu, color: Color(0xFF94A3B8)), onPressed: () {}),
         IconButton(
           icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
           onPressed: () async {
             await _authService.signOut();
             if (mounted) {
               Navigator.of(context).pushAndRemoveUntil(
                 MaterialPageRoute(builder: (_) => const LoginScreen()),
                 (route) => false,
               );
             }
           },
         ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    return Column(
      children: [
        Text("Welcome, $_userName", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        const Text("Ready for departure", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildBlinkingEye() {
    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Float Animation wraps the Eye
          AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnimation.value),
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _blinkController,
              builder: (context, child) {
                return Transform.scale(
                  scaleY: _blinkAnimation.value, // Squashes vertically to blink
                  alignment: Alignment.center,
                  child: Container(
                    width: 160,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1021),
                      // Creates the almond/eye shape
                      borderRadius: const BorderRadius.all(Radius.elliptical(160, 100)),
                      border: Border.all(color: const Color(0xFF137FEC).withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF137FEC).withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: Center(
                      // Outer Iris
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF137FEC), width: 2),
                          gradient: RadialGradient(
                            colors: [const Color(0xFF137FEC).withOpacity(0.8), Colors.transparent],
                            stops: const [0.5, 1.0],
                          ),
                        ),
                        // Inner Pupil
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(color: Colors.white, blurRadius: 10, spreadRadius: 2)
                              ]
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Standby Badge at the bottom of the bounding box
          Positioned(
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      const Text("STANDBY", style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return const Text(
      "Ready to safeguard your drive. Tap Start Journey to begin monitoring.",
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16, fontWeight: FontWeight.w500, height: 1.5),
    );
  }

  Widget _buildStartButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF137FEC).withOpacity(0.4), blurRadius: 30, spreadRadius: 0)],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF137FEC),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: const Color(0xFF137FEC).withOpacity(0.2), width: 4)),
          elevation: 0,
        ),
        onPressed: _startJourney,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow, size: 24),
            SizedBox(width: 12),
            Text("Start Journey", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

   Widget _buildSecondaryActions() {
     return _buildSecondaryButton(Icons.refresh, "Recalibrate", onTap: _recalibrate);
   }

   Widget _buildSecondaryButton(IconData icon, String label, {VoidCallback? onTap}) {
     return Material(
       color: Colors.transparent,
       child: InkWell(
         onTap: onTap ?? () {},
         borderRadius: BorderRadius.circular(12),
         child: Container(
           padding: const EdgeInsets.symmetric(vertical: 16),
           decoration: BoxDecoration(
             color: Colors.white.withOpacity(0.05),
             borderRadius: BorderRadius.circular(12),
             border: Border.all(color: Colors.white.withOpacity(0.05)),
           ),
           child: Row(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(icon, color: const Color(0xFF94A3B8), size: 20),
               const SizedBox(width: 8),
               Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500)),
             ],
           ),
         ),
       ),
     );
   }

}
