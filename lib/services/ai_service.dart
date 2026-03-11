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
    try {
      print('🌐 API CALL: Sending request to Trinity via OpenRouter...');
      final response = await http.post(
        Uri.parse(AppConstants.openRouterUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${AppConstants.openRouterApiKey}",
        },
        body: jsonEncode({
          "model": AppConstants.aiModel,
          "messages": messages,
          "max_tokens": 150,
          "temperature": 0.7,
        }),
      ).timeout(const Duration(seconds: 30));

      print('🌐 API RESPONSE: Status ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? content = data['choices']?[0]?['message']?['content'];
        if (content != null) {
          String cleanResp = _cleanResponse(content);
          print('🌐 AI SAID: $cleanResp');
          _history.add({"role": "assistant", "content": cleanResp});
          return cleanResp;
        } else {
          print('🌐 API ERROR: No content in response: ${response.body}');
        }
      } else {
        print('🌐 API ERROR: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print("🌐 API EXCEPTION: $e");
    }
    return fallback;
  }

  String _cleanResponse(String text) {
    text = text.replaceAll(RegExp(r'<think>.*?</think>', multiLine: true, dotAll: true), '');
    return text.replaceAll(RegExp(r'[\[\]\{\}*"]'), '').trim();
  }
}