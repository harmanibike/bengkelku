import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../business/data/business_profile_repository.dart';

class BusinessStoryPage extends StatefulWidget {
  const BusinessStoryPage({super.key});

  @override
  State<BusinessStoryPage> createState() => _BusinessStoryPageState();
}

class _BusinessStoryPageState extends State<BusinessStoryPage> {
  final _posterKey = GlobalKey();
  final _titleController = TextEditingController(text: 'Informasi untuk Pelanggan');
  final _messageController = TextEditingController(
    text: 'Kami ingin menginformasikan bahwa bengkel dan toko kami akan tutup sementara.',
  );
  final _dateController = TextEditingController();
  final _returnDateController = TextEditingController();

  String _kind = 'libur';
  String _businessName = 'Bengkel & Toko Sepeda';
  String _businessAddress = '';
  String _businessContact = '';
  String _businessLogoPath = '';
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessName();
  }

  Future<void> _loadBusinessName() async {
    try {
      final profile = await BusinessProfileRepository().getProfile();
      final name = profile['business_name']?.trim();
      if (mounted) {
        setState(() {
          if (name != null && name.isNotEmpty) _businessName = name;
          _businessAddress = profile['business_address']?.trim() ?? '';
          _businessContact = (profile['business_whatsapp']?.trim().isNotEmpty == true
                  ? profile['business_whatsapp']!.trim()
                  : profile['business_phone']?.trim()) ?? '';
          _businessLogoPath = profile['business_logo_path']?.trim() ?? '';
        });
      }
    } catch (_) {
      // Poster tetap dapat dibuat bila profil usaha belum diisi.
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _dateController.dispose();
    _returnDateController.dispose();
    super.dispose();
  }

  void _selectKind(String? value) {
    if (value == null) return;
    setState(() {
      _kind = value;
      if (value == 'libur') {
        _titleController.text = 'Informasi Libur';
        _messageController.text =
            'Kami informasikan bahwa bengkel dan toko kami tutup sementara. Terima kasih atas pengertiannya.';
      } else if (value == 'jam') {
        _titleController.text = 'Perubahan Jam Operasional';
        _messageController.text =
            'Ada perubahan jam operasional. Silakan perhatikan informasi jadwal terbaru kami.';
      } else {
        _titleController.text = 'Promo Spesial';
        _messageController.text =
            'Nikmati promo spesial untuk kebutuhan sepeda Anda. Silakan hubungi kami untuk informasi lebih lanjut.';
      }
    });
  }

  Future<void> _shareStory() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final context = _posterKey.currentContext;
      final boundary = context?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Pratinjau poster belum siap.');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('Gagal membuat gambar poster.');

      final Uint8List bytes = byteData.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/bike_pos_story_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${_titleController.text.trim()}\n${_messageController.text.trim()}',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Belum berhasil membuat poster: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _poster() {
    final date = _dateController.text.trim();
    final returnDate = _returnDateController.text.trim();
    return RepaintBoundary(
      key: _posterKey,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF104B91), Color(0xFF168B9B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_businessLogoPath.isNotEmpty && File(_businessLogoPath).existsSync())
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Image.file(File(_businessLogoPath), fit: BoxFit.contain),
                )
              else
                const Icon(Icons.pedal_bike_rounded, color: Colors.white, size: 38),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _kind == 'libur' ? 'PENGUMUMAN' : _kind == 'jam' ? 'INFO OPERASIONAL' : 'PROMO',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _titleController.text.trim().isEmpty
                    ? 'Pengumuman'
                    : _titleController.text.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _messageController.text.trim(),
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
              ),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  _kind == 'libur' ? 'Mulai: $date' : 'Berlaku: $date',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
              if (returnDate.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  'Buka kembali: $returnDate',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
              const Spacer(),
              Container(height: 1, color: Colors.white38),
              const SizedBox(height: 14),
              Text(
                _businessName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              if (_businessAddress.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_businessAddress, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 9)),
              ],
              if (_businessContact.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text('WhatsApp: $_businessContact', style: const TextStyle(color: Colors.white, fontSize: 10)),
              ],
              const SizedBox(height: 5),
              const Text('Terima kasih atas kepercayaan Anda',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengumuman & Story')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'Buat pengumuman untuk Status WhatsApp Business',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(
              labelText: 'Jenis pengumuman',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'libur', child: Text('Informasi libur')),
              DropdownMenuItem(value: 'jam', child: Text('Jam operasional')),
              DropdownMenuItem(value: 'promo', child: Text('Promosi / diskon')),
            ],
            onChanged: _selectKind,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Judul poster', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Isi pengumuman', border: OutlineInputBorder(), alignLabelWithHint: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dateController,
            decoration: const InputDecoration(labelText: 'Tanggal mulai / berlaku (opsional)', hintText: 'Contoh: 28–30 November 2026', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _returnDateController,
            decoration: const InputDecoration(labelText: 'Tanggal buka kembali (opsional)', hintText: 'Contoh: 1 Desember 2026', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          const Text('Pratinjau Story 9:16', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300), child: _poster())),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sharing ? null : _shareStory,
            icon: _sharing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.share_rounded),
            label: Text(_sharing ? 'Menyiapkan poster…' : 'Bagikan ke WhatsApp / aplikasi lain'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aplikasi akan membuka menu berbagi Android. Pilih WhatsApp Business, lalu pilih Status dan unggah sendiri. POS tidak mengirim atau menerbitkan Status secara otomatis.',
            style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }
}
