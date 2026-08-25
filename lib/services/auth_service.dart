import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  String? get uid => _client.auth.currentUser?.id;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );

    // Create profile row
    if (response.user != null) {
      await _client.from('profiles').upsert({
        'id': response.user!.id,
        'name': name,
        'email': email,
      });
    }

    // Ensure session is cleared so user must explicitly sign in after registration
    await _client.auth.signOut();

    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<String> getUserName() async {
    final user = currentUser;
    if (user == null) return 'Driver';

    // Try user metadata first (cached, fast)
    final metaName = user.userMetadata?['name'];
    if (metaName != null && metaName.toString().isNotEmpty) {
      return metaName.toString();
    }

    // Fallback to profiles table
    try {
      final data = await _client
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      return data?['name'] ?? 'Driver';
    } catch (_) {
      return 'Driver';
    }
  }
}
