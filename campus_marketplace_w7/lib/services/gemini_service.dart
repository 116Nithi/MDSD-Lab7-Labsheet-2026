import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiService {
  static const String _model = 'gemini-3.6-flash';
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  Future<String> generateText(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ไม่พบ Gemini API Key กรุณารันด้วย --dart-define=GEMINI_API_KEY=your_key',
      );
    }

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_model:generateContent',
      {'key': _apiKey},
    );

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'Gemini API ตอบกลับสถานะ ${response.statusCode}: '
          '${_apiErrorMessage(response.body)}',
        );
      }

      final result = _decodeObject(response.body);
      final candidates = result['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw Exception('Gemini ไม่ส่งผลลัพธ์กลับมา กรุณาลองใหม่อีกครั้ง');
      }

      final candidate = candidates.first;
      if (candidate is! Map<String, dynamic>) {
        throw Exception('รูปแบบคำตอบจาก Gemini ไม่ถูกต้อง');
      }
      if (candidate['finishReason'] == 'SAFETY') {
        throw Exception('คำขอนี้ถูกระบบความปลอดภัยของ Gemini ปฏิเสธ');
      }

      final content = candidate['content'];
      final parts = content is Map<String, dynamic> ? content['parts'] : null;
      if (parts is! List) {
        throw Exception('Gemini ไม่ส่งข้อความกลับมา กรุณาลองใหม่อีกครั้ง');
      }

      final text = parts
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text.isEmpty) {
        throw Exception('Gemini ไม่ส่งข้อความกลับมา กรุณาลองใหม่อีกครั้ง');
      }
      return text;
    } on TimeoutException {
      throw Exception('Gemini ใช้เวลาตอบกลับเกิน 20 วินาที กรุณาลองใหม่');
    } on http.ClientException {
      throw Exception('เชื่อมต่อ Gemini ไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ต');
    }
  }
}

Map<String, dynamic> _decodeObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Gemini response is not a JSON object');
  }
  return decoded;
}

String _apiErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        return error['message'] as String;
      }
    }
  } on FormatException {
    return body;
  }
  return body;
}
