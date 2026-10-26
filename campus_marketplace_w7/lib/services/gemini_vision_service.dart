import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeminiVisionService {
  // รุ่นหลักก่อน ถ้าเซิร์ฟเวอร์ยุ่ง (503) จะลองรุ่นสำรองตามลำดับ
  static const List<String> _models = [
    'gemini-3.5-flash-lite',
    'gemini-3.7-flash',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
  ];
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  Future<Map<String, dynamic>> analyzeProductImage(
    File imageFile,
    String prompt,
  ) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ไม่พบ Gemini API Key กรุณารันด้วย --dart-define=GEMINI_API_KEY=your_key',
      );
    }

    final imageBytes = await imageFile.readAsBytes();
    final imageBase64 = base64Encode(imageBytes);
    final extension = imageFile.path.toLowerCase().split('.').last;
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };

    try {
      http.Response? response;
      for (final model in _models) {
        final uri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/$model:generateContent',
          {'key': _apiKey},
        );
        try {
          response = await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt},
                        {
                          'inline_data': {
                            'mime_type': mimeType,
                            'data': imageBase64,
                          },
                        },
                      ],
                    },
                  ],
                  'generationConfig': {
                    'responseMimeType': 'application/json',
                    'responseSchema': {
                      'type': 'OBJECT',
                      'properties': {
                        'title': {'type': 'STRING'},
                        'category': {
                          'type': 'STRING',
                          'enum': [
                            'หนังสือเรียน',
                            'อุปกรณ์อิเล็กทรอนิกส์',
                            'ของแต่งหอพัก',
                            'เสื้อผ้า',
                            'อื่นๆ',
                          ],
                        },
                        'description': {'type': 'STRING'},
                      },
                      'required': ['title', 'category', 'description'],
                    },
                  },
                }),
              )
              .timeout(const Duration(seconds: 25));
        } on TimeoutException {
          debugPrint('Gemini $model ช้าเกิน 25 วินาที ลองรุ่นถัดไป');
          response = null;
          continue;
        }
        if (response.statusCode != 503 && response.statusCode != 429) break;
        debugPrint('Gemini $model ตอบ ${response.statusCode} ลองรุ่นถัดไป');
      }

      if (response == null) {
        throw TimeoutException('Gemini timeout');
      }
      if (response.statusCode != 200) {
        throw Exception(
          'Gemini API ตอบกลับสถานะ ${response.statusCode}: '
          '${_apiErrorMessage(response.body)}',
        );
      }

      final result = _decodeObject(response.body);
      final candidates = result['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw Exception(
          'AI ไม่สามารถวิเคราะห์ภาพนี้ได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม ลองใช้ภาพอื่น',
        );
      }

      final candidate = candidates.first;
      if (candidate is! Map<String, dynamic>) {
        throw Exception('รูปแบบคำตอบจาก Gemini ไม่ถูกต้อง');
      }
      if (candidate['finishReason'] == 'SAFETY') {
        throw Exception(
          'เนื้อหาที่วิเคราะห์เข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาใช้ภาพอื่น',
        );
      }

      final content = candidate['content'];
      final parts = content is Map<String, dynamic> ? content['parts'] : null;
      if (parts is! List) {
        throw Exception('Gemini ไม่ส่งข้อมูลวิเคราะห์กลับมา กรุณาลองใหม่');
      }

      final responseText = parts
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (responseText.isEmpty) {
        throw Exception('Gemini ไม่ส่งข้อมูลวิเคราะห์กลับมา กรุณาลองใหม่');
      }

      final decodedDraft = jsonDecode(responseText);
      if (decodedDraft is! Map<String, dynamic>) {
        throw const FormatException('Gemini response is not a JSON object');
      }
      return decodedDraft;
    } on TimeoutException {
      throw Exception('Gemini ใช้เวลาวิเคราะห์ช้าเกินไป กรุณาลองใหม่');
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
