import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/listing_draft.dart';
import '../services/gemini_vision_service.dart';

class SellItemPage extends StatefulWidget {
  const SellItemPage({super.key});

  @override
  State<SellItemPage> createState() => _SellItemPageState();
}

class _SellItemPageState extends State<SellItemPage> {
  static const String _prompt = '''
คุณคือผู้ช่วยเขียนประกาศขายของมือสองในตลาดนัดออนไลน์สำหรับนักศึกษามหาวิทยาลัย
จากรูปภาพสินค้าที่แนบมา ให้วิเคราะห์แล้วตอบกลับเป็น JSON เท่านั้น ตามโครงสร้างนี้:
{
  "title": "ชื่อประกาศสั้นกระชับ ไม่เกิน 40 ตัวอักษร",
  "category": "หมวดหมู่ที่เหมาะสมที่สุด เลือกจาก: หนังสือเรียน, อุปกรณ์อิเล็กทรอนิกส์, ของแต่งหอพัก, เสื้อผ้า, อื่นๆ",
  "description": "คำบรรยายสินค้า 2-3 ประโยค ที่ดึงดูดผู้ซื้อและบอกสภาพของสินค้าตามที่เห็นในภาพ"
}
ห้ามตอบข้อความอื่นนอกเหนือจาก JSON ดังกล่าว
''';


  File? _image;
  bool _isAnalyzing = false;
  String? _errorMessage;
  ListingDraft? _draft;
  ListingDraft? _confirmedDraft;
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // ย่อรูปก่อนส่ง Gemini เพื่อลดขนาดข้อมูลที่อัปโหลดและเวลารอ
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _draft = null;
      _confirmedDraft = null;
      _errorMessage = null;
    });
  }

  Future<void> _analyze() async {
    final image = _image;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปภาพสินค้าก่อน')),
      );
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _draft = null;
      _confirmedDraft = null;
    });
    try {
      final json = await GeminiVisionService().analyzeProductImage(
        image,
        _prompt,
      );
      final draft = ListingDraft.fromJson(json);
      if (!mounted) return;
      _titleController.text = draft.title;
      _categoryController.text = draft.category;
      _descriptionController.text = draft.description;
      setState(() => _draft = draft);
    } catch (e) {
      debugPrint('Gemini Vision error: $e');
      if (!mounted) return;
      setState(() => _errorMessage = '$e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _confirm() {
    final draft = ListingDraft(
      title: _titleController.text.trim(),
      category: _categoryController.text.trim(),
      description: _descriptionController.text.trim(),
    );
    setState(() => _confirmedDraft = draft);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('บันทึกร่างประกาศ "${draft.title}" แล้ว')),
    );
  }

  Widget _buildResult() {
    if (_isAnalyzing) {
      return const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 8),
          Text('AI กำลังวิเคราะห์...'),
        ],
      );
    }
    if (_errorMessage != null) {
      return Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      );
    }
    if (_draft == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI แนะนำให้แล้ว กรุณาตรวจทานและแก้ไขก่อนยืนยัน'),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'ชื่อประกาศ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _categoryController,
          decoration: const InputDecoration(
            labelText: 'หมวดหมู่',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'คำบรรยาย',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: const Text('ยืนยันร่างประกาศ'),
          ),
        ),
        if (_confirmedDraft != null) ...[
          const SizedBox(height: 12),
          Text(
            'ร่างฉบับสุดท้าย: ${_confirmedDraft!.title} '
            '(${_confirmedDraft!.category})',
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลงประกาศขายสินค้า')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 240,
              width: double.infinity,
              child: _image != null
                  ? Image.file(_image!, fit: BoxFit.contain)
                  : Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image, size: 64),
                    ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('เลือกรูปภาพสินค้า'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _analyze,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('ให้ AI ช่วยแนะนำ'),
            ),
            const SizedBox(height: 16),
            _buildResult(),
          ],
        ),
      ),
    );
  }
}
