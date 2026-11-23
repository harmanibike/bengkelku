import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';

import '../../../core/auth/auth_session.dart';

import '../../settings/data/account_repository.dart';

import '../../customers/data/customer_repository.dart';
import '../data/service_repository.dart';
import '../data/service_pricing_repository.dart';
import 'service_photo_helper.dart';

class ServiceIntakePage extends StatefulWidget {
  const ServiceIntakePage({super.key});

  @override
  State<ServiceIntakePage> createState() => _ServiceIntakePageState();
}

class _ServiceIntakePageState extends State<ServiceIntakePage> {
  final _formKey = GlobalKey<FormState>();
  final _customerRepository = CustomerRepository();
  final _serviceRepository = ServiceRepository();
  final _pricingRepository = ServicePricingRepository();

  final _complaintController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _estimateController = TextEditingController(text: '0');
  final _laborController = TextEditingController(text: '0');
  final _partsController = TextEditingController(text: '0');
  final _directPartsCostController = TextEditingController(text: '0');
  final _otherDirectCostController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _downPaymentController = TextEditingController(text: '0');
  final _mechanicController = TextEditingController();
  final _notesController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _guestBicycleBrandController = TextEditingController();
  final _guestBicycleModelController = TextEditingController();
  final _guestBicycleTypeController = TextEditingController();
  final _guestBicycleColorController = TextEditingController();
  final _guestBicycleSerialController = TextEditingController();
  bool _guestMode = false;
  List<Map<String, Object?>> _customerSearchResults = [];
  bool _searchingCustomers = false;
  int _customerSearchToken = 0;

  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _bicycles = [];
  List<Map<String, Object?>> _serviceCatalog = [];
  List<Map<String, Object?>> _mechanics = [];
  int? _selectedMechanicId;
  int? _selectedCatalogServiceId;
  bool _laborPriceUnlocked = false;
  int? _selectedCustomerId;
  int? _selectedBicycleId;
  String? _beforePhotoPath;
  bool _loading = true;
  bool _saving = false;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadServiceCatalog();
    _loadMechanics();
  }

  @override
  void dispose() {
    _complaintController.dispose();
    _diagnosisController.dispose();
    _estimateController.dispose();
    _laborController.dispose();
    _partsController.dispose();
    _directPartsCostController.dispose();
    _otherDirectCostController.dispose();
    _discountController.dispose();
    _downPaymentController.dispose();
    _mechanicController.dispose();
    _notesController.dispose();
    _customerSearchController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestBicycleBrandController.dispose();
    _guestBicycleModelController.dispose();
    _guestBicycleTypeController.dispose();
    _guestBicycleColorController.dispose();
    _guestBicycleSerialController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await _customerRepository.getCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Gagal memuat pelanggan: $error');
    }
  }

  Future<void> _searchCustomers(String keyword) async {
    final token = ++_customerSearchToken;
    if (keyword.trim().isEmpty) {
      if (mounted) setState(() {
        _customerSearchResults = [];
        _searchingCustomers = false;
      });
      return;
    }
    setState(() => _searchingCustomers = true);
    try {
      final results = await _customerRepository.getCustomers(
        keyword: keyword.trim(),
        limit: 20,
      );
      if (!mounted || token != _customerSearchToken) return;
      setState(() {
        _customerSearchResults = results;
        _searchingCustomers = false;
      });
    } catch (error) {
      if (!mounted || token != _customerSearchToken) return;
      setState(() => _searchingCustomers = false);
      _showMessage('Gagal mencari pelanggan: $error');
    }
  }

  void _onCustomerSearchChanged(String keyword) {
    if (_selectedCustomerId != null) {
      setState(() {
        _selectedCustomerId = null;
        _selectedBicycleId = null;
        _bicycles = [];
      });
    }
    _searchCustomers(keyword);
  }

  void _selectCustomer(Map<String, Object?> customer) {
    final id = customer['id'] as int;
    _customerSearchController.text = customer['name']?.toString() ?? '';
    setState(() {
      _selectedCustomerId = id;
      _selectedBicycleId = null;
      _bicycles = [];
      _customerSearchResults = [];
    });
    _loadBicycles(id);
  }

  Future<void> _loadBicycles(int customerId) async {
    try {
      final bicycles = await _customerRepository.getBicycles(
        customerId: customerId,
      );
      if (!mounted) return;
      setState(() {
        _bicycles = bicycles;
        _selectedBicycleId = null;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal memuat sepeda: $error');
    }
  }


  Future<void> _loadMechanics() async {
    try {
      final accounts = await AccountRepository().getAccounts();
      if (!mounted) return;
      setState(() => _mechanics = accounts.where((account) =>
          account['role'] == 'mechanic' && (account['is_active'] as int? ?? 0) == 1).toList());
    } catch (error) {
      _showMessage('Gagal memuat daftar mekanik: $error');
    }
  }

  Future<void> _loadServiceCatalog() async {
    try {
      final items = await _pricingRepository.getServices(activeOnly: true);
      if (mounted) setState(() => _serviceCatalog = items);
    } catch (error) {
      _showMessage('Gagal memuat master jasa: $error');
    }
  }

  Future<void> _unlockLaborPrice() async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Otorisasi Admin'),
        content: TextField(
          controller: pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'PIN admin'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final valid = await _pricingRepository.verifyAdminPin(pin.text);
      if (valid && mounted) {
        setState(() => _laborPriceUnlocked = true);
        _showMessage('Perubahan harga manual diizinkan untuk sesi ini.');
      } else if (mounted) {
        _showMessage('PIN admin salah atau belum dibuat di menu Harga Jasa.');
      }
    }
    pin.dispose();
  }

  Future<void> _pickBeforePhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final path = await ServicePhotoHelper.pickAndSave(context);
      if (!mounted) return;
      if (path != null) {
        setState(() => _beforePhotoPath = path);
        _showMessage('Foto kondisi awal berhasil dipilih.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal mengambil foto: $error');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  int _amount(TextEditingController controller) {
    return parseCurrencyInput(controller.text);
  }

  int get _total {
    final labor = _amount(_laborController);
    final parts = _amount(_partsController);
    final base = labor + parts > 0
        ? labor + parts
        : _amount(_estimateController);
    final result = base - _amount(_discountController);
    return result < 0 ? 0 : result;
  }

  String _rupiah(int amount) {
    final value = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && (value.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(value[i]);
    }
    return 'Rp$buffer';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_guestMode && (_selectedCustomerId == null || _selectedBicycleId == null)) {
      _showMessage('Pilih pelanggan dan sepeda terlebih dahulu.');
      return;
    }
    if (_guestMode &&
        (_guestNameController.text.trim().isEmpty ||
         _guestBicycleBrandController.text.trim().isEmpty)) {
      _showMessage('Nama pelanggan dan merek sepeda wajib diisi.');
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await _serviceRepository.createServiceOrder(
        customerId: _guestMode ? null : _selectedCustomerId,
        bicycleId: _guestMode ? null : _selectedBicycleId,
        guestCustomerName: _guestMode ? _guestNameController.text : null,
        guestCustomerPhone: _guestMode ? _guestPhoneController.text : null,
        guestBicycleBrand: _guestMode ? _guestBicycleBrandController.text : null,
        guestBicycleModel: _guestMode ? _guestBicycleModelController.text : null,
        guestBicycleType: _guestMode ? _guestBicycleTypeController.text : null,
        guestBicycleColor: _guestMode ? _guestBicycleColorController.text : null,
        guestBicycleSerialNumber: _guestMode ? _guestBicycleSerialController.text : null,
        complaint: _complaintController.text,
        diagnosis: _diagnosisController.text,
        estimatedCost: _amount(_estimateController),
        laborCost: _amount(_laborController),
        partsCost: _amount(_partsController),
        directPartsCost: _amount(_directPartsCostController),
        otherDirectCost: _amount(_otherDirectCostController),
        discount: _amount(_discountController),
        downPayment: _amount(_downPaymentController),
        mechanicName: _selectedMechanicId == null ? _mechanicController.text : _mechanics.firstWhere((m) => m['id'] == _selectedMechanicId)['display_name']?.toString(),
        assignedMechanicId: _selectedMechanicId,
        notes: _notesController.text,
        beforePhotoPath: _beforePhotoPath,
      );

      if (!mounted) return;
      _showMessage('Penerimaan servis berhasil disimpan (ID: $id).');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal menyimpan penerimaan servis: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _moneyField(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      readOnly: readOnly,
      onTap: onTap,
      inputFormatters: const [CurrencyInputFormatter()],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'Rp ',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return '$label wajib diisi';
        }
        if (value != null &&
            value.trim().isNotEmpty &&
            _amount(controller) < 0) {
          return 'Nominal tidak valid';
        }
        return null;
      },
    );
  }

  String _bicycleLabel(Map<String, Object?> bicycle) {
    final brand = bicycle['brand']?.toString() ?? '';
    final model = bicycle['model']?.toString() ?? '';
    final type = bicycle['bicycle_type']?.toString() ?? '';
    final serial = bicycle['serial_number']?.toString() ?? '';
    final name = [brand, model].where((e) => e.isNotEmpty).join(' ');
    final details = [type, serial].where((e) => e.isNotEmpty).join(' • ');
    return details.isEmpty ? name : '$name ($details)';
  }

  Widget _beforePhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Foto kondisi sepeda sebelum servis', Icons.camera_alt_outlined),
        const Text(
          'Dokumentasikan kondisi sepeda saat diterima sebagai bukti awal servis.',
        ),
        const SizedBox(height: 10),
        ServicePhotoHelper.preview(_beforePhotoPath, height: 190),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickingPhoto ? null : _pickBeforePhoto,
          icon: _pickingPhoto
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(
            _pickingPhoto
                ? 'Memproses foto...'
                : _beforePhotoPath == null
                    ? 'Ambil / pilih foto kondisi awal'
                    : 'Ganti foto kondisi awal',
          ),
        ),
        if (_beforePhotoPath != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _beforePhotoPath = null),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus foto pilihan'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Penerimaan Servis')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('Data pelanggan & sepeda', Icons.pedal_bike),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Pelanggan Terdaftar'),
                            selected: !_guestMode,
                            onSelected: (_) => setState(() {
                              _guestMode = false;
                              _guestNameController.clear();
                              _guestPhoneController.clear();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('Pelanggan Umum'),
                            selected: _guestMode,
                            onSelected: (_) => setState(() {
                              _guestMode = true;
                              _selectedCustomerId = null;
                              _selectedBicycleId = null;
                              _bicycles = [];
                              _customerSearchController.clear();
                              _customerSearchResults = [];
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_guestMode) ...[
                        TextFormField(
                          controller: _guestNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nama pelanggan *',
                            hintText: 'Nama pelanggan umum',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _guestMode &&
                                  (value == null || value.trim().isEmpty)
                              ? 'Nama pelanggan wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Nomor HP (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestBicycleBrandController,
                          decoration: const InputDecoration(
                            labelText: 'Merek sepeda *',
                            hintText: 'Contoh: Polygon',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _guestMode &&
                                  (value == null || value.trim().isEmpty)
                              ? 'Merek sepeda wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestBicycleModelController,
                          decoration: const InputDecoration(
                            labelText: 'Model sepeda (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextFormField(
                            controller: _guestBicycleTypeController,
                            decoration: const InputDecoration(
                              labelText: 'Jenis sepeda',
                              border: OutlineInputBorder(),
                            ),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: TextFormField(
                            controller: _guestBicycleColorController,
                            decoration: const InputDecoration(
                              labelText: 'Warna',
                              border: OutlineInputBorder(),
                            ),
                          )),
                        ]),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _guestBicycleSerialController,
                          decoration: const InputDecoration(
                            labelText: 'Nomor rangka (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else ...[
                      TextFormField(
                        controller: _customerSearchController,
                        decoration: InputDecoration(
                          labelText: 'Cari pelanggan *',
                          hintText: 'Ketik nama atau nomor HP',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchingCustomers
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  tooltip: 'Hapus pencarian',
                                  onPressed: () {
                                    _customerSearchController.clear();
                                    setState(() {
                                      _selectedCustomerId = null;
                                      _selectedBicycleId = null;
                                      _bicycles = [];
                                      _customerSearchResults = [];
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _onCustomerSearchChanged,
                        validator: (_) => _selectedCustomerId == null
                            ? 'Cari dan pilih pelanggan terlebih dahulu'
                            : null,
                      ),
                      if (_selectedCustomerId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              'Pelanggan dipilih: ${_customerSearchController.text}',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                            )),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedCustomerId = null;
                                _selectedBicycleId = null;
                                _bicycles = [];
                                _customerSearchController.clear();
                              }),
                              child: const Text('Ganti'),
                            ),
                          ]),
                        ),
                      if (_customerSearchResults.isNotEmpty && _selectedCustomerId == null)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _customerSearchResults.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final customer = _customerSearchResults[index];
                              final name = customer['name']?.toString() ?? '-';
                              final phone = customer['phone']?.toString() ?? '';
                              return ListTile(
                                dense: true,
                                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                title: Text(name),
                                subtitle: Text(phone.isEmpty ? 'Tanpa nomor HP' : phone),
                                onTap: () => _selectCustomer(customer),
                              );
                            },
                          ),
                        )
                      else if (_customerSearchController.text.trim().isNotEmpty &&
                          _selectedCustomerId == null && !_searchingCustomers)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Pelanggan tidak ditemukan. Pilih mode Pelanggan Umum untuk pelanggan tanpa data terdaftar.',
                            style: TextStyle(color: Colors.deepOrange)),
                        ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedBicycleId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sepeda *',
                          border: OutlineInputBorder(),
                        ),
                        items: _bicycles.map((bicycle) {
                          return DropdownMenuItem<int>(
                            value: bicycle['id'] as int,
                            child: Text(
                              _bicycleLabel(bicycle),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _selectedCustomerId == null
                            ? null
                            : (value) => setState(
                                  () => _selectedBicycleId = value,
                                ),
                        validator: (value) =>
                            value == null ? 'Pilih sepeda' : null,
                      ),
                      if (_selectedCustomerId != null && _bicycles.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Pelanggan ini belum memiliki data sepeda. '
                            'Tambahkan sepeda melalui menu Sepeda.',
                            style: TextStyle(color: Colors.deepOrange),
                          ),
                        ),
                      ],
                      _sectionTitle('Keluhan & pemeriksaan', Icons.build_outlined),
                      TextFormField(
                        controller: _complaintController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Keluhan pelanggan *',
                          hintText: 'Contoh: Rem belakang bunyi dan kurang pakem',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Keluhan wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _diagnosisController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Hasil pemeriksaan awal',
                          hintText: 'Isi jika sudah dilakukan pemeriksaan',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      _beforePhotoSection(),
                      _sectionTitle('Estimasi & pembayaran', Icons.payments_outlined),

                      if (_serviceCatalog.isNotEmpty)
                        DropdownButtonFormField<int>(
                          initialValue: _selectedCatalogServiceId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Master jasa / harga standar',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _serviceCatalog.map((item) {
                            final label = item['name'].toString() +
                                ' • Rp' +
                                (item['standard_price'] ?? 0).toString();
                            return DropdownMenuItem<int>(
                              value: item['id'] as int,
                              child: Text(label, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (id) {
                            if (id == null) return;
                            final item = _serviceCatalog.firstWhere(
                              (entry) => entry['id'] == id,
                            );
                            setState(() {
                              _selectedCatalogServiceId = id;
                              _laborController.text =
                                  (item['standard_price'] ?? 0).toString();
                              _laborPriceUnlocked = false;
                            });
                          },
                        ),
                      if (_serviceCatalog.isNotEmpty)
                        const SizedBox(height: 8),
                      _moneyField('Estimasi biaya', _estimateController),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField('Jasa servis', _laborController, readOnly: !_laborPriceUnlocked, onTap: _laborPriceUnlocked ? null : _unlockLaborPrice),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _moneyField('Biaya sparepart', _partsController),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (AuthSession.instance.isAdmin) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField('Modal sparepart', _directPartsCostController),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _moneyField('Biaya langsung lain', _otherDirectCostController),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          'Isi biaya modal/bahan yang benar-benar dikeluarkan. Ini bukan harga jual pelanggan dan tidak otomatis mengurangi stok.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField('Diskon', _discountController),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _moneyField('Uang muka (DP)', _downPaymentController),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total tagihan sementara',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                _rupiah(_total),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _sectionTitle('Informasi tambahan', Icons.assignment_ind_outlined),
                      if (_mechanics.isNotEmpty)
                        DropdownButtonFormField<int>(
                          initialValue: _selectedMechanicId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tugaskan kepada mekanik', border: OutlineInputBorder()),
                          items: _mechanics.map((mechanic) => DropdownMenuItem<int>(
                            value: mechanic['id'] as int,
                            child: Text(mechanic['display_name']?.toString() ?? 'Mekanik'),
                          )).toList(),
                          onChanged: (value) => setState(() => _selectedMechanicId = value),
                        )
                      else
                        TextFormField(
                          controller: _mechanicController,
                          decoration: const InputDecoration(labelText: 'Nama mekanik (opsional)', border: OutlineInputBorder()),
                        ),
                      if (_mechanics.isNotEmpty)
                        const Padding(padding: EdgeInsets.only(top: 5), child: Text('Penugasan ini menentukan servis yang terlihat pada akun Mekanik.', style: TextStyle(fontSize: 11, color: Colors.grey))),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Catatan tambahan',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Menyimpan...' : 'Simpan Penerimaan Servis',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }
}
