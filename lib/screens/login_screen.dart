import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;
  String? _success;
  String? _emailError;
  String? _passwordError;
  String? _nameError;

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    setState(() {
      _error = null;
      _success = null;
      _emailError = null;
      _passwordError = null;
      _nameError = null;
    });
  }

  bool _validateInputs() {
    _clearErrors();
    bool isValid = true;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (!_isLogin && name.isEmpty) {
      _nameError = "Full name is required";
      isValid = false;
    }

    if (email.isEmpty) {
      _emailError = "Email address is required";
      isValid = false;
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _emailError = "Enter a valid email address (e.g. user@example.com)";
      isValid = false;
    }

    if (password.isEmpty) {
      _passwordError = "Password is required";
      isValid = false;
    } else if (password.length < 6) {
      _passwordError = "Password must be at least 6 characters";
      isValid = false;
    }

    if (!isValid) {
      setState(() {});
    }

    return isValid;
  }

  Future<void> _submit() async {
    if (!_validateInputs()) return;

    setState(() {
      _isLoading = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    try {
      if (_isLogin) {
        // Sign In logic: strictly checks credentials against registered users
        await _auth.signIn(
          email: email,
          password: password,
        );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        // Register logic: creates account & profile in DB, then signs out
        await _auth.signUp(
          email: email,
          password: password,
          name: name,
        );

        if (mounted) {
          setState(() {
            _isLogin = true;
            _success = "Registration successful! Account created for $email. Please sign in below.";
            _passwordController.clear();
          });
        }
      }
    } catch (e) {
      final cleanMsg = e.toString().replaceAll(RegExp(r'AuthException\(message:\s*'), '').replaceAll(')', '').trim();
      setState(() {
        if (_isLogin) {
          _emailError = "Invalid email or unregistered account";
          _passwordError = "Invalid password or credentials";
          _error = "Login failed: Account not found or incorrect credentials. If you do not have an account yet, please sign up first.";
        } else {
          if (cleanMsg.toLowerCase().contains("already registered") || cleanMsg.toLowerCase().contains("already exists")) {
            _emailError = "This email is already registered";
            _error = "An account with this email already exists. Please switch to Sign In.";
          } else {
            _error = "Registration failed: $cleanMsg";
          }
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF137FEC), Color(0xFF0B1021)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF137FEC).withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.visibility, color: Colors.white, size: 36),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "DriveAware",
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? "Welcome back" : "Create your account",
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                      ),
                      const SizedBox(height: 32),

                      // SUCCESS INDICATOR BANNER
                      if (_success != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF065F46).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _success!,
                                  style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ERROR INDICATOR BANNER
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7F1D1D).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isLogin) ...[
                              _buildTextField(
                                controller: _nameController,
                                hint: "Full Name",
                                icon: Icons.person_outline,
                                errorText: _nameError,
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildTextField(
                              controller: _emailController,
                              hint: "Email",
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              errorText: _emailError,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _passwordController,
                              hint: "Password",
                              icon: Icons.lock_outline,
                              obscure: true,
                              errorText: _passwordError,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF137FEC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _isLogin ? "Sign In" : "Register Account",
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _clearErrors();
                          });
                        },
                        child: Text(
                          _isLogin ? "Don't have an account? Register now" : "Already have an account? Sign in",
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        ),
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
  }) {
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              onChanged: (_) {
                if (errorText != null) {
                  setState(() {
                    _emailError = null;
                    _passwordError = null;
                    _nameError = null;
                    _error = null;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: Icon(icon, color: hasError ? const Color(0xFFEF4444) : const Color(0xFF64748B)),
                suffixIcon: hasError ? const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20) : null,
                filled: true,
                fillColor: hasError ? const Color(0xFFEF4444).withOpacity(0.08) : Colors.white.withOpacity(0.05),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: hasError ? const Color(0xFFEF4444) : Colors.white.withOpacity(0.1),
                    width: hasError ? 1.5 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: hasError ? const Color(0xFFEF4444) : const Color(0xFF137FEC),
                    width: 2.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFFCA5A5), size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

