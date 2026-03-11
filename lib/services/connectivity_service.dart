import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Lightweight connectivity checker.
///
/// Uses a simple HTTP HEAD request instead of adding a dependency.
/// Caches result for [_cacheDuration] to avoid hammering the network.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  static const Duration _cacheDuration = Duration(seconds: 30);

  bool _lastKnownOnline = true;
  DateTime? _lastCheck;

  /// Returns `true` if the device appears to have internet connectivity.
  /// Result is cached for 30 seconds to avoid repeated network calls.
  Future<bool> get isOnline async {
    if (_lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _cacheDuration) {
      return _lastKnownOnline;
    }

    try {
      final response = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      _lastKnownOnline = response.statusCode == 200;
    } catch (_) {
      _lastKnownOnline = false;
    }

    _lastCheck = DateTime.now();
    debugPrint('🌐 Connectivity check: ${_lastKnownOnline ? "ONLINE" : "OFFLINE"}');
    return _lastKnownOnline;
  }

  /// Force-refresh the cached connectivity status.
  void invalidateCache() {
    _lastCheck = null;
  }
}
