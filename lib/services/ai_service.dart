import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/place_model.dart';

class AIService {
  

  final List<Map<String, String>> _history = [];

  void endConversation() {
    _history.clear();
  }

  /// 1. HANDLES VOICE COMMANDS
  Future<String> chatWithTars(String userMessage, {String? location, PlaceModel? nearestStop}) async {
    String stopInfo = nearestStop != null 
        ? "Nearest safe stop: ${nearestStop.name} (${nearestStop.distanceKm.toStringAsFixed(1)} km away)." 
        : "No known safe stops nearby.";

    String systemPrompt = """
    You are TARS, a tactical AI co-pilot.
    Personality: Witty, sarcastic, logical.
    Context: Driver is asking a question.
    Location: ${location ?? "Unknown"}.
    $stopInfo
    Constraint: You MUST respond in conversational Tagalog (Taglish is fine). Keep answers short (under 20 words). Plain text only.
    """;

    _history.add({"role": "user", "content": userMessage});

    // Keep history manageable (last 10 messages)
    if (_history.length > 10) {
      _history.removeRange(0, _history.length - 10);
    }

    final List<Map<String, dynamic>> messages = [
      {"role": "system", "content": systemPrompt},
      ..._history,
    ];

    return _makeApiCall(
        messages,
        fallback: "Nawala ang signal. Tumutok lang sa kalsada."
    );
  }

  Future<String> _makeApiCall(List<Map<String, dynamic>> messages, {required String fallback}) async {
    final apiKey = AppConstants.openRouterApiKey;
    final apiUrl = AppConstants.openRouterUrl;
    final primaryModel = AppConstants.aiModel;

    // openrouter/free first — it auto-picks the fastest available free model
    final List<String> candidateModels = [
      'openrouter/free',
      primaryModel,
      'google/gemma-4-26b-a4b-it:free',
      'inclusionai/ling-3.0-flash:free',
    ];

    final modelsToTry = candidateModels.toSet().toList();

    for (final model in modelsToTry) {
      try {
        print('🌐 Trying $model...');
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $apiKey",
            "HTTP-Referer": "https://github.com/driveaware",
            "X-Title": "DriveAware",
          },
          body: jsonEncode({
            "model": model,
            "messages": messages,
            "max_tokens": 150,
            "temperature": 0.7,
          }),
        ).timeout(const Duration(seconds: 10));

        // Skip instantly on non-retryable errors
        if (response.statusCode == 404 || response.statusCode == 401) {
          print('⏭️ $model → ${response.statusCode}, skipping');
          continue;
        }

        if (response.statusCode == 200 && response.body.isNotEmpty) {
          final data = jsonDecode(response.body);
          String? content = data['choices']?[0]?['message']?['content'];
          if (content != null && content.trim().isNotEmpty) {
            String cleanResp = _cleanResponse(content);
            print('✅ AI ($model): $cleanResp');
            _history.add({"role": "assistant", "content": cleanResp});
            return cleanResp;
          }
        }
        print('⚠️ $model → HTTP ${response.statusCode}, empty content');
      } catch (e) {
        print('💥 $model → $e');
      }
    }

    print('🚫 All models failed');
    return fallback;
  }

  String _cleanResponse(String text) {
    text = text.replaceAll(RegExp(r'<think>.*?</think>', multiLine: true, dotAll: true), '');
    return text.replaceAll(RegExp(r'[\[\]\{\}*"]'), '').trim();
  }
}