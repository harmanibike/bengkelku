import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../business/data/business_profile_repository.dart';
import '../data/business_story_repository.dart';

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
  String _template = 'biru';
  String _businessName = 'Bengkel & Toko Sepeda';
  String _businessAddress = '';
  String _businessContact = '';
  String? _announcementLogoPath;
  bool _sharing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(DateTime.now());
    _loadBusinessName();
    _loadAnnouncementLogo();
  }

  Future<File> _customLogoFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/business_story_custom_logo');
  }

  Future<void> _loadAnnouncementLogo() async {
    try {
      final file = await _customLogoFile();
      if (await file.exists() && mounted) {
        setState(() => _announcementLogoPath = file.path);
      }
    } catch (_) {
      // Logo bawaan tetap digunakan bila file khusus belum tersedia.
    }
  }

  Future<void> _pickAnnouncementLogo() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      final target = await _customLogoFile();
      await File(picked.path).copy(target.path);
      if (mounted) {
        setState(() => _announcementLogoPath = target.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo pengumuman berhasil diperbarui.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih logo: $error')),
        );
      }
    }
  }

  Future<void> _resetAnnouncementLogo() async {
    try {
      final file = await _customLogoFile();
      if (await file.exists()) await file.delete();
      if (mounted) {
        setState(() => _announcementLogoPath = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo bawaan pengumuman digunakan kembali.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengembalikan logo bawaan: $error')),
        );
      }
    }
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

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final parsed = controller.text.split('-');
    DateTime initial = now;
    if (parsed.length == 3) {
      final day = int.tryParse(parsed[0]);
      final month = int.tryParse(parsed[1]);
      final year = int.tryParse(parsed[2]);
      if (day != null && month != null && year != null) {
        initial = DateTime(year, month, day);
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal pengumuman',
    );
    if (picked != null && mounted) {
      setState(() => controller.text = _formatDate(picked));
    }
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


  Future<void> _saveStory() async {
    if (_saving) return;
    if (_titleController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judul dan isi pengumuman wajib diisi.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await BusinessStoryRepository().save(
        kind: _kind,
        title: _titleController.text,
        message: _messageController.text,
        dateLabel: _dateController.text,
        returnDateLabel: _returnDateController.text,
        template: _template,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengumuman tersimpan di riwayat.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pengumuman: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showHistory() async {
    try {
      final items = await BusinessStoryRepository().getAll();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Riwayat Pengumuman', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Belum ada pengumuman tersimpan.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final kind = item['kind']?.toString() ?? 'libur';
                            final label = kind == 'libur' ? 'Libur' : kind == 'jam' ? 'Jam operasional' : 'Promo';
                            return ListTile(
                              leading: const Icon(Icons.campaign_outlined),
                              title: Text(item['title']?.toString() ?? 'Pengumuman'),
                              subtitle: Text('$label • ${item['created_at'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                setState(() {
                                  _kind = kind;
                                  _titleController.text = item['title']?.toString() ?? '';
                                  _messageController.text = item['message']?.toString() ?? '';
                                  _dateController.text = item['date_label']?.toString() ?? '';
                                  _returnDateController.text = item['return_date_label']?.toString() ?? '';
                                  _template = item['template']?.toString() ?? 'biru';
                                });
                                Navigator.pop(sheetContext);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka riwayat: $error')),
        );
      }
    }
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

  IconData get _announcementIcon => _kind == 'libur'
      ? Icons.event_busy_rounded
      : _kind == 'jam'
          ? Icons.schedule_rounded
          : Icons.local_offer_rounded;

  Widget _poster() {
    final colors = switch (_template) {
      'hijau' => const [Color(0xFF075B50), Color(0xFF27A58A)],
      'hangat' => const [Color(0xFF8C351C), Color(0xFFE58A32)],
      'ungu' => const [Color(0xFF452477), Color(0xFF9670D5)],
      'merah' => const [Color(0xFF8F2032), Color(0xFFE45B57)],
      'gelap' => const [Color(0xFF202A38), Color(0xFF536477)],
      'biru' => const [Color(0xFF104B91), Color(0xFF168B9B)],
      _ => const [Color(0xFF104B91), Color(0xFF168B9B)],
    };
    final date = _dateController.text.trim();
    final returnDate = _returnDateController.text.trim();
    return RepaintBoundary(
      key: _posterKey,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.pedal_bike_rounded,
                    size: 230,
                    color: Colors.white.withValues(alpha: 0.075),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
                ),
                child: ClipOval(
                  child: _announcementLogoPath != null &&
                          File(_announcementLogoPath!).existsSync()
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.file(
                            File(_announcementLogoPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              _announcementIcon,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(_announcementIcon, color: Colors.white, size: 34),
                            Positioned(
                              right: 8,
                              bottom: 7,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: Icon(Icons.pedal_bike_rounded, color: colors.first, size: 15),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
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
            key: ValueKey('story-kind-$_kind'),
            initialValue: _kind,
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
          DropdownButtonFormField<String>(
            key: ValueKey('story-template-$_template'),
            initialValue: _template,
            decoration: const InputDecoration(labelText: 'Desain poster', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 'biru', child: Text('Biru profesional')),
              DropdownMenuItem(value: 'hijau', child: Text('Hijau segar')),
              DropdownMenuItem(value: 'hangat', child: Text('Oranye hangat')),
              DropdownMenuItem(value: 'ungu', child: Text('Ungu elegan')),
              DropdownMenuItem(value: 'merah', child: Text('Merah tegas')),
              DropdownMenuItem(value: 'gelap', child: Text('Abu-abu modern')),
            ],
            onChanged: (value) { if (value != null) setState(() => _template = value); },
          ),
          const SizedBox(height: 12),
          const Text('Logo Pengumuman', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
                child: ClipOval(
                  child: _announcementLogoPath != null &&
                          File(_announcementLogoPath!).existsSync()
                      ? Image.file(File(_announcementLogoPath!), fit: BoxFit.contain)
                      : Icon(_announcementIcon, size: 30, color: Colors.blueGrey),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickAnnouncementLogo,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Pilih dari Galeri'),
                    ),
                    TextButton.icon(
                      onPressed: _announcementLogoPath == null ? null : _resetAnnouncementLogo,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Gunakan Logo Bawaan'),
                    ),
                  ],
                ),
              ),
            ],
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
            readOnly: true,
            onTap: () => _pickDate(_dateController),
            decoration: const InputDecoration(
              labelText: 'Tanggal mulai / berlaku',
              hintText: 'Pilih tanggal',
              suffixIcon: Icon(Icons.calendar_month_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _returnDateController,
            readOnly: true,
            onTap: () => _pickDate(_returnDateController),
            decoration: const InputDecoration(
              labelText: 'Tanggal buka kembali (opsional)',
              hintText: 'Pilih tanggal',
              suffixIcon: Icon(Icons.calendar_month_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 18),
          const Text('Pratinjau Story 9:16', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300), child: _poster())),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _saving ? null : _saveStory,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bookmark_add_outlined),
            label: Text(_saving ? 'Menyimpan…' : 'Simpan ke Riwayat'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showHistory,
            icon: const Icon(Icons.history_rounded),
            label: const Text('Buka Riwayat Pengumuman'),
          ),
          const SizedBox(height: 8),
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
