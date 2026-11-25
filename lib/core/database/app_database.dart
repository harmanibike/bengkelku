import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'bengkelku_pos.db';
  static const int currentVersion = 39;
  static const int _databaseVersion = currentVersion;

  Database? _database;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final fullPath = p.join(databasePath, _databaseName);

    return openDatabase(
      fullPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    final batch = db.batch();

    // Identitas perangkat jaringan. Token hanya disimpan dalam bentuk hash.
    batch.execute('''
      CREATE TABLE paired_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen_at TEXT,
        revoked_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_paired_devices_active ON paired_devices(revoked_at, created_at)');
    // Kode pairing bersifat sekali pakai dan memiliki batas waktu.
    batch.execute('''
      CREATE TABLE device_pairing_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code_hash TEXT NOT NULL UNIQUE,
        expires_at TEXT NOT NULL,
        consumed_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    batch.execute('CREATE INDEX idx_device_pairing_codes_expiry ON device_pairing_codes(expires_at, consumed_at)');
    // Pembatasan percobaan pairing disimpan agar tidak hilang saat aplikasi dimulai ulang.
    batch.execute('''
      CREATE TABLE device_pairing_attempt_limits (
        client_address TEXT PRIMARY KEY,
        window_started_at TEXT NOT NULL,
        failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK(failed_attempts >= 0),
        blocked_until TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_device_pairing_attempt_limits_blocked ON device_pairing_attempt_limits(blocked_until)');

    // Jejak aktivitas akun; user_id tanpa foreign key agar histori tetap utuh.
    batch.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        user_name TEXT NOT NULL,
        user_role TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_type TEXT,
        entity_id INTEGER,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_activity_logs_created ON activity_logs(created_at DESC, id DESC)');
    batch.execute('CREATE INDEX idx_activity_logs_user ON activity_logs(user_id, created_at DESC)');
    // Akun lokal untuk Admin, Kasir, dan Mekanik.
    batch.execute('''
      CREATE TABLE app_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        role TEXT NOT NULL CHECK(role IN ('admin', 'cashier', 'mechanic')),
        phone TEXT,
        profile_photo_path TEXT,
        pin_hash TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');

    // Pengaturan aplikasi.
    batch.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        setting_key TEXT NOT NULL UNIQUE,
        setting_value TEXT,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Data pelanggan.
    batch.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        email TEXT,
        notes TEXT,
        photo_base64 TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');

    // Data sepeda pelanggan.
    batch.execute('''
      CREATE TABLE bicycles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        brand TEXT,
        model TEXT,
        bicycle_type TEXT,
        color TEXT,
        frame_size TEXT,
        serial_number TEXT UNIQUE,
        purchase_date TEXT,
        warranty_until TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (customer_id)
          REFERENCES customers(id)
          ON DELETE SET NULL
      )
    ''');

    // Data pemasok.
    batch.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        email TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Produk, sparepart, dan aksesoris.
    batch.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT UNIQUE,
        barcode TEXT UNIQUE,
        name TEXT NOT NULL,
        category TEXT,
        brand TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        purchase_price INTEGER NOT NULL DEFAULT 0,
        selling_price INTEGER NOT NULL DEFAULT 0,
        wholesale_price INTEGER NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        minimum_stock INTEGER NOT NULL DEFAULT 0,
        track_stock INTEGER NOT NULL DEFAULT 1,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');

    // Varian produk. Stok dan identitas barcode/SKU dikelola terpisah dari produk induk.
    batch.execute('''
      CREATE TABLE product_variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        sku TEXT UNIQUE,
        barcode TEXT UNIQUE,
        purchase_price INTEGER NOT NULL DEFAULT 0,
        selling_price INTEGER NOT NULL DEFAULT 0,
        wholesale_price INTEGER NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        minimum_stock INTEGER NOT NULL DEFAULT 0,
        track_stock INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('CREATE INDEX idx_product_variants_product ON product_variants(product_id, is_active, name)');
    batch.execute('CREATE INDEX idx_product_variants_barcode ON product_variants(barcode)');

    // Master kategori produk. Nama kategori unik tanpa membedakan huruf besar/kecil.
    batch.execute('''
      CREATE TABLE product_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');

    // Faktur pembelian dari pemasok.
    batch.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        supplier_id INTEGER,
        subtotal INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        paid INTEGER NOT NULL DEFAULT 0,
        return_credit INTEGER NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        status TEXT NOT NULL DEFAULT 'active',
        cancelled_at TEXT,
        cancel_reason TEXT,
        purchase_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER,
        variant_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_cost INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        purchase_id INTEGER,
        amount INTEGER NOT NULL,
        payment_method TEXT,
        payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL
      )
    ''');

    batch.execute('CREATE INDEX idx_purchases_supplier ON purchases(supplier_id, purchase_date)');
    batch.execute('CREATE INDEX idx_purchase_items_purchase ON purchase_items(purchase_id)');
    batch.execute('CREATE INDEX idx_supplier_payments_purchase ON supplier_payments(purchase_id, payment_date)');

    // Retur pembelian ke pemasok.
    batch.execute('''
      CREATE TABLE purchase_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        return_number TEXT NOT NULL UNIQUE,
        total_amount INTEGER NOT NULL DEFAULT 0,
        credit_applied INTEGER NOT NULL DEFAULT 0,
        refund_received INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        cancelled_at TEXT,
        cancel_reason TEXT,
        notes TEXT,
        return_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('''
      CREATE TABLE purchase_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_return_id INTEGER NOT NULL,
        purchase_item_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        stock_deducted INTEGER NOT NULL DEFAULT 0,
        unit_cost INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_return_id) REFERENCES purchase_returns(id) ON DELETE CASCADE,
        FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_purchase_returns_purchase ON purchase_returns(purchase_id, return_date)');
    batch.execute('CREATE INDEX idx_purchase_return_items_return ON purchase_return_items(purchase_return_id)');
    batch.execute('''
      CREATE TABLE purchase_return_batch_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        return_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_cost INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (return_id) REFERENCES purchase_returns(id) ON DELETE RESTRICT,
        FOREIGN KEY (return_item_id) REFERENCES purchase_return_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_purchase_return_batch_alloc_return ON purchase_return_batch_allocations(return_id, return_item_id)');

    batch.execute('''
      CREATE TABLE supplier_return_credit_applications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        purchase_id INTEGER NOT NULL,
        supplier_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (return_id) REFERENCES purchase_returns(id) ON DELETE RESTRICT,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE RESTRICT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_return_credit_applications_return ON supplier_return_credit_applications(return_id, created_at)');
    batch.execute('CREATE INDEX idx_return_credit_applications_purchase ON supplier_return_credit_applications(purchase_id, created_at)');


    // Perintah kerja servis.
    batch.execute('''
      CREATE TABLE service_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        bicycle_id INTEGER,
        customer_name TEXT,
        customer_phone TEXT,
        bicycle_brand TEXT,
        bicycle_model TEXT,
        bicycle_type TEXT,
        bicycle_color TEXT,
        bicycle_serial_number TEXT,
        complaint TEXT,
        diagnosis TEXT,
        service_status TEXT NOT NULL DEFAULT 'waiting',
        estimated_cost INTEGER NOT NULL DEFAULT 0,
        labor_cost INTEGER NOT NULL DEFAULT 0,
        parts_cost INTEGER NOT NULL DEFAULT 0,
        direct_parts_cost INTEGER NOT NULL DEFAULT 0,
        other_direct_cost INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        total_cost INTEGER NOT NULL DEFAULT 0,
        down_payment INTEGER NOT NULL DEFAULT 0,
        remaining_payment INTEGER NOT NULL DEFAULT 0,
        mechanic_name TEXT,
        assigned_mechanic_id INTEGER,
        queue_number INTEGER,
        queue_date TEXT,
        queue_priority INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        completed_at TEXT,
        notes TEXT,
        before_photo_path TEXT,
        after_photo_path TEXT,
        FOREIGN KEY (customer_id)
          REFERENCES customers(id)
          ON DELETE SET NULL,
        FOREIGN KEY (bicycle_id)
          REFERENCES bicycles(id)
          ON DELETE SET NULL
      )
    ''');

    batch.execute('CREATE UNIQUE INDEX idx_service_daily_queue ON service_orders(queue_date, queue_number) WHERE queue_number IS NOT NULL');
    batch.execute('CREATE INDEX idx_service_queue_order ON service_orders(queue_date, queue_priority DESC, queue_number ASC)');

    // Riwayat perubahan status servis untuk jejak pengerjaan.
    batch.execute('''
      CREATE TABLE service_status_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        old_status TEXT,
        new_status TEXT NOT NULL,
        note TEXT,
        changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_service_status_history_order
      ON service_status_history(service_order_id, changed_at)
    ''');

    // Riwayat audit perubahan biaya modal servis untuk database baru.
    batch.execute('''
      CREATE TABLE service_direct_cost_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        old_direct_parts_cost INTEGER NOT NULL DEFAULT 0,
        new_direct_parts_cost INTEGER NOT NULL DEFAULT 0,
        old_other_direct_cost INTEGER NOT NULL DEFAULT 0,
        new_other_direct_cost INTEGER NOT NULL DEFAULT 0,
        changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_service_direct_cost_history_order ON service_direct_cost_history(service_order_id, changed_at, id)');

    // Rincian pekerjaan dan sparepart servis.
    batch.execute('''
      CREATE TABLE service_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        product_id INTEGER,
        item_name TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'service',
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id)
          ON DELETE CASCADE,
        FOREIGN KEY (product_id)
          REFERENCES products(id)
          ON DELETE SET NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE service_part_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_cost INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (service_order_item_id) REFERENCES service_order_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_service_part_allocations_item ON service_part_allocations(service_order_item_id)');
    batch.execute('''
      CREATE TABLE service_part_change_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        request_type TEXT NOT NULL CHECK(request_type IN ('add', 'cancel')),
        service_order_item_id INTEGER,
        product_id INTEGER,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price INTEGER NOT NULL DEFAULT 0,
        mechanic_note TEXT,
        status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'rejected')),
        proposed_by_id INTEGER,
        proposed_by_name TEXT,
        proposed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        reviewed_by_id INTEGER,
        reviewed_by_name TEXT,
        customer_approved INTEGER NOT NULL DEFAULT 0,
        customer_approval_note TEXT,
        reviewed_at TEXT,
        FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT,
        FOREIGN KEY (service_order_item_id) REFERENCES service_order_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_service_part_change_requests_order ON service_part_change_requests(service_order_id, status, proposed_at)');
    batch.execute('''
      CREATE TABLE service_estimate_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        old_estimated_cost INTEGER NOT NULL DEFAULT 0,
        new_estimated_cost INTEGER NOT NULL DEFAULT 0,
        old_labor_cost INTEGER NOT NULL DEFAULT 0,
        new_labor_cost INTEGER NOT NULL DEFAULT 0,
        old_parts_cost INTEGER NOT NULL DEFAULT 0,
        new_parts_cost INTEGER NOT NULL DEFAULT 0,
        old_discount INTEGER NOT NULL DEFAULT 0,
        new_discount INTEGER NOT NULL DEFAULT 0,
        old_total_cost INTEGER NOT NULL DEFAULT 0,
        new_total_cost INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        customer_approved INTEGER NOT NULL DEFAULT 0,
        customer_approval_note TEXT,
        changed_by_id INTEGER,
        changed_by_name TEXT,
        changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_service_estimate_history_order ON service_estimate_history(service_order_id, changed_at, id)');

    // Transaksi penjualan.
    batch.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        customer_name TEXT,
        subtotal INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        tax INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        paid INTEGER NOT NULL DEFAULT 0,
        change_amount INTEGER NOT NULL DEFAULT 0,
        payment_method TEXT,
        payment_status TEXT NOT NULL DEFAULT 'paid',
        transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        FOREIGN KEY (customer_id)
          REFERENCES customers(id)
          ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE held_sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        buyer_name TEXT NOT NULL DEFAULT '',
        items_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Rincian barang penjualan.
    batch.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price INTEGER NOT NULL DEFAULT 0,
        purchase_price INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id)
          REFERENCES sales(id)
          ON DELETE CASCADE,
        FOREIGN KEY (product_id)
          REFERENCES products(id)
          ON DELETE SET NULL
      )
    ''');

    // Riwayat pergerakan stok.
    batch.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        movement_type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        stock_before INTEGER NOT NULL DEFAULT 0,
        stock_after INTEGER NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (product_id)
          REFERENCES products(id)
          ON DELETE RESTRICT
      )
    ''');

    batch.execute('''
      CREATE TABLE inventory_cost_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        purchase_id INTEGER,
        purchase_item_id INTEGER,
        batch_code TEXT,
        quantity_received INTEGER NOT NULL,
        quantity_remaining INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notes TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL,
        FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_inventory_cost_batches_product ON inventory_cost_batches(product_id, received_at, id)');
    batch.execute('CREATE INDEX idx_inventory_cost_batches_variant ON inventory_cost_batches(variant_id, received_at, id)');
    batch.execute('CREATE INDEX idx_stock_movements_variant ON stock_movements(variant_id, created_at DESC)');
    batch.execute('CREATE INDEX idx_purchase_items_variant ON purchase_items(variant_id)');
    batch.execute('''
      CREATE TABLE sale_batch_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        sale_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_cost INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_sale_batch_allocations_sale ON sale_batch_allocations(sale_id, sale_item_id)');

    // Retur penjualan untuk instalasi baru.
    batch.execute('''
      CREATE TABLE sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        return_number TEXT NOT NULL UNIQUE,
        total_amount INTEGER NOT NULL DEFAULT 0 CHECK(total_amount >= 0),
        refunded_amount INTEGER NOT NULL DEFAULT 0 CHECK(refunded_amount >= 0),
        notes TEXT,
        return_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('''
      CREATE TABLE sale_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_return_id INTEGER NOT NULL,
        sale_item_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price INTEGER NOT NULL DEFAULT 0,
        unit_cost INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_return_id) REFERENCES sale_returns(id) ON DELETE RESTRICT,
        FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE sale_return_batch_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_return_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_cost INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (sale_return_item_id) REFERENCES sale_return_items(id) ON DELETE RESTRICT,
        FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_sale_returns_sale ON sale_returns(sale_id, return_date, id)');
    batch.execute('CREATE INDEX idx_sale_return_items_return ON sale_return_items(sale_return_id)');
    batch.execute('CREATE INDEX idx_sale_return_items_sale_item ON sale_return_items(sale_item_id)');
    batch.execute('CREATE INDEX idx_sale_return_batch_alloc_item ON sale_return_batch_allocations(sale_return_item_id)');


    // Sesi dan rincian stok opname untuk instalasi baru.
    batch.execute('''
      CREATE TABLE stock_opname_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opname_number TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'draft',
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        applied_at TEXT
      )
    ''');
    batch.execute('''
      CREATE TABLE stock_opname_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        sku TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        system_quantity INTEGER NOT NULL DEFAULT 0,
        counted_quantity INTEGER,
        variance INTEGER,
        counted_at TEXT,
        FOREIGN KEY (session_id) REFERENCES stock_opname_sessions(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_stock_opname_items_session ON stock_opname_items(session_id, product_name)');

    // Kas masuk dan keluar.
    batch.execute('''
      CREATE TABLE cash_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_type TEXT NOT NULL,
        category TEXT,
        description TEXT,
        amount INTEGER NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id INTEGER,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Saldo deposit pelanggan: kewajiban kepada pelanggan, bukan omzet.
    batch.execute('''
      CREATE TABLE customer_wallet_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL CHECK(entry_type IN ('deposit', 'service_payment', 'sale_payment', 'refund', 'adjustment')),
        amount INTEGER NOT NULL CHECK(amount > 0),
        balance_after INTEGER NOT NULL CHECK(balance_after >= 0),
        description TEXT,
        reference_type TEXT,
        reference_id INTEGER,
        payment_method TEXT,
        created_by_id INTEGER,
        created_by_name TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_customer_wallet_customer ON customer_wallet_ledger(customer_id, created_at DESC, id DESC)');
    batch.execute('CREATE INDEX idx_customer_wallet_reference ON customer_wallet_ledger(reference_type, reference_id)');
    // Tip dicatat terpisah dari omzet dan saldo deposit pelanggan.
    batch.execute('''
      CREATE TABLE tip_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount INTEGER NOT NULL CHECK(amount > 0),
        source_type TEXT NOT NULL CHECK(source_type IN ('service_order', 'sale', 'manual')),
        source_id INTEGER,
        recipient_account_id INTEGER,
        recipient_name TEXT,
        payment_method TEXT,
        status TEXT NOT NULL DEFAULT 'held' CHECK(status IN ('held', 'handed_over', 'cancelled')),
        note TEXT,
        received_by_id INTEGER,
        received_by_name TEXT,
        received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        handed_over_by_id INTEGER,
        handed_over_by_name TEXT,
        handed_over_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_tip_transactions_date ON tip_transactions(received_at DESC, id DESC)');
    batch.execute('CREATE INDEX idx_tip_transactions_source ON tip_transactions(source_type, source_id)');

    // Log pengingat untuk instalasi baru.
    batch.execute('''
      CREATE TABLE receivable_reminder_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receivable_type TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        phone TEXT NOT NULL,
        opened_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_receivable_reminder_record
      ON receivable_reminder_logs(receivable_type, record_id, opened_at)
    ''');


    // Master jasa, pengaturan harga, dan audit perubahan harga.
    batch.execute('''
      CREATE TABLE service_catalog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        standard_price INTEGER NOT NULL DEFAULT 0 CHECK(standard_price >= 0),
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_service_catalog_active ON service_catalog(is_active, sort_order, name)');
    batch.execute('''
      CREATE TABLE service_price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_id INTEGER NOT NULL,
        old_price INTEGER NOT NULL,
        new_price INTEGER NOT NULL,
        change_reason TEXT,
        changed_by TEXT NOT NULL DEFAULT 'Admin',
        changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (service_id) REFERENCES service_catalog(id) ON DELETE RESTRICT
      )
    ''');
    batch.execute('CREATE INDEX idx_service_price_history_service ON service_price_history(service_id, changed_at)');

    // Snapshot nota yang sudah diterbitkan; payload tidak berubah saat transaksi diedit.
    batch.execute('''
      CREATE TABLE receipt_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_type TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id INTEGER NOT NULL,
        document_number TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        issued_at TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    batch.execute('CREATE INDEX idx_receipt_snapshots_source ON receipt_snapshots(source_type, source_id, issued_at, id)');

    // Index untuk mempercepat pencarian.
    batch.execute('''
      CREATE INDEX idx_customers_name
      ON customers(name)
    ''');

    batch.execute('''
      CREATE INDEX idx_customers_phone
      ON customers(phone)
    ''');

    batch.execute('''
      CREATE INDEX idx_bicycles_customer
      ON bicycles(customer_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_products_name
      ON products(name)
    ''');

    batch.execute('''
      CREATE INDEX idx_products_category
      ON products(category)
    ''');

    batch.execute('''
      CREATE INDEX idx_service_status
      ON service_orders(service_status)
    ''');

    batch.execute('''
      CREATE INDEX idx_service_customer
      ON service_orders(customer_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_sales_date
      ON sales(transaction_date)
    ''');

    batch.execute('''
      CREATE INDEX idx_stock_product
      ON stock_movements(product_id)
    ''');

    await batch.commit(noResult: true);
    await db.execute('''
      CREATE TABLE loyalty_point_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        sale_id INTEGER,
        reference_type TEXT NOT NULL,
        reference_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        points INTEGER NOT NULL,
        eligible_amount INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('CREATE INDEX idx_loyalty_ledger_customer ON loyalty_point_ledger(customer_id, created_at DESC)');
    await db.execute('CREATE UNIQUE INDEX idx_loyalty_ledger_reference ON loyalty_point_ledger(reference_type, reference_id, entry_type)');
    await db.execute('''
      CREATE TABLE loyalty_rewards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        reward_type TEXT NOT NULL DEFAULT 'gift',
        points_cost INTEGER NOT NULL CHECK(points_cost > 0),
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_loyalty_rewards_active ON loyalty_rewards(is_active, points_cost, name)');
    await db.execute('''
      CREATE TABLE loyalty_redemptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        reward_id INTEGER,
        reward_name TEXT NOT NULL,
        points_spent INTEGER NOT NULL CHECK(points_spent > 0),
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
        FOREIGN KEY (reward_id) REFERENCES loyalty_rewards(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_loyalty_redemptions_customer ON loyalty_redemptions(customer_id, created_at DESC)');
    await _seedDefaultServiceCatalog(db);
    await _seedDefaultProductCategories(db);
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Varian produk ditambahkan secara aditif; data produk dan transaksi lama tidak diubah.
    if (oldVersion < 38) {
      await db.execute('''
        CREATE TABLE product_variants (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          sku TEXT UNIQUE,
          barcode TEXT UNIQUE,
          purchase_price INTEGER NOT NULL DEFAULT 0,
          selling_price INTEGER NOT NULL DEFAULT 0,
          wholesale_price INTEGER NOT NULL DEFAULT 0,
          stock INTEGER NOT NULL DEFAULT 0,
          minimum_stock INTEGER NOT NULL DEFAULT 0,
          track_stock INTEGER NOT NULL DEFAULT 1,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX idx_product_variants_product ON product_variants(product_id, is_active, name)');
      await db.execute('CREATE INDEX idx_product_variants_barcode ON product_variants(barcode)');
    }

    // Hubungkan transaksi pembelian, batch biaya, dan pergerakan stok ke varian.
    // Database lama/minimal untuk migrasi dapat tidak memiliki semua modul tabel.
    if (oldVersion < 39) {
      final existingTables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']?.toString()).toSet();

      if (existingTables.contains('purchase_items')) {
        await db.execute('ALTER TABLE purchase_items ADD COLUMN variant_id INTEGER');
        await db.execute('CREATE INDEX idx_purchase_items_variant ON purchase_items(variant_id)');
      }
      if (existingTables.contains('stock_movements')) {
        await db.execute('ALTER TABLE stock_movements ADD COLUMN variant_id INTEGER');
        await db.execute('CREATE INDEX idx_stock_movements_variant ON stock_movements(variant_id, created_at DESC)');
      }
      if (existingTables.contains('inventory_cost_batches')) {
        await db.execute('ALTER TABLE inventory_cost_batches ADD COLUMN variant_id INTEGER');
        await db.execute('CREATE INDEX idx_inventory_cost_batches_variant ON inventory_cost_batches(variant_id, received_at, id)');
      }
    }

    // Simpan apakah stok benar-benar dikurangi saat retur dibuat.
    // NULL pada database lama berarti histori harus diverifikasi dari stock_movements.
    if (oldVersion < 34) {
      await db.execute(
        'ALTER TABLE purchase_return_items ADD COLUMN stock_deducted INTEGER',
      );
    }

    // Pairing perangkat Server-Client. Migrasi aditif; data bengkel lama tidak disentuh.
    if (oldVersion < 33) {
      await db.execute('''
        CREATE TABLE paired_devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          token_hash TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          last_seen_at TEXT,
          revoked_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_paired_devices_active ON paired_devices(revoked_at, created_at)');
      await db.execute('''
        CREATE TABLE device_pairing_codes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code_hash TEXT NOT NULL UNIQUE,
          expires_at TEXT NOT NULL,
          consumed_at TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('CREATE INDEX idx_device_pairing_codes_expiry ON device_pairing_codes(expires_at, consumed_at)');
    }

    // Rate limit pairing aditif; histori dan transaksi database lama tidak disentuh.
    if (oldVersion < 35) {
      await db.execute('''
        CREATE TABLE device_pairing_attempt_limits (
          client_address TEXT PRIMARY KEY,
          window_started_at TEXT NOT NULL,
          failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK(failed_attempts >= 0),
          blocked_until TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_device_pairing_attempt_limits_blocked ON device_pairing_attempt_limits(blocked_until)');
    }

    // Profil akun: nomor HP dan foto disimpan per akun, tanpa mengubah role.
    // Beberapa database legacy/test tidak memiliki tabel app_users; jangan gagalkan
    // seluruh migrasi hanya karena tabel akun belum pernah dibuat.
    if (oldVersion < 36) {
      final accountTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_users' LIMIT 1",
      );
      if (accountTable.isNotEmpty) {
        final columns = await db.rawQuery('PRAGMA table_info(app_users)');
        final names = columns.map((column) => column['name']?.toString()).toSet();
        if (!names.contains('phone')) {
          await db.execute('ALTER TABLE app_users ADD COLUMN phone TEXT');
        }
        if (!names.contains('profile_photo_path')) {
          await db.execute('ALTER TABLE app_users ADD COLUMN profile_photo_path TEXT');
        }
      }
    }

    // Metode pembayaran kas untuk pemisahan kas tunai dan nontunai.
    // Cek tabel/kolom agar aman untuk database legacy yang tidak lengkap.
    if (oldVersion < 37) {
      final cashTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cash_transactions' LIMIT 1",
      );
      if (cashTable.isNotEmpty) {
        final columns = await db.rawQuery('PRAGMA table_info(cash_transactions)');
        final names = columns.map((column) => column['name']?.toString()).toSet();
        if (!names.contains('payment_method')) {
          await db.execute("ALTER TABLE cash_transactions ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'");
        }
        // Backfill pembayaran pemasok dari riwayat pembayaran yang sudah tersimpan.
        final supplierPaymentsTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'supplier_payments' LIMIT 1",
        );
        if (supplierPaymentsTable.isNotEmpty) {
          await db.execute('''
            UPDATE cash_transactions
            SET payment_method = COALESCE((
              SELECT sp.payment_method FROM supplier_payments sp
              WHERE sp.purchase_id = cash_transactions.reference_id
                AND sp.payment_date = cash_transactions.transaction_date
              ORDER BY sp.id DESC LIMIT 1
            ), payment_method)
            WHERE reference_type = 'purchase_payment'
          ''');
        }
        final salesTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sales' LIMIT 1",
        );
        if (salesTable.isNotEmpty) {
          await db.execute('''
            UPDATE cash_transactions
            SET payment_method = COALESCE((
              SELECT s.payment_method FROM sales s
              WHERE s.id = cash_transactions.reference_id
            ), payment_method)
            WHERE reference_type = 'sale'
          ''');
        }
      }
    }

    // Pastikan tabel pengaturan tersedia pada semua database lama tanpa menghapus data.
    if (oldVersion < 26) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          setting_key TEXT NOT NULL UNIQUE,
          setting_value TEXT,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }

    // Buku poin loyalty: migrasi aditif, transaksi dan pelanggan lama tetap utuh.
    if (oldVersion < 27) {
      await db.execute('''
        CREATE TABLE loyalty_point_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER,
          sale_id INTEGER,
          reference_type TEXT NOT NULL,
          reference_id INTEGER NOT NULL,
          entry_type TEXT NOT NULL,
          points INTEGER NOT NULL,
          eligible_amount INTEGER NOT NULL DEFAULT 0,
          description TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('CREATE INDEX idx_loyalty_ledger_customer ON loyalty_point_ledger(customer_id, created_at DESC)');
      await db.execute('CREATE UNIQUE INDEX idx_loyalty_ledger_reference ON loyalty_point_ledger(reference_type, reference_id, entry_type)');
    }

    // Katalog reward loyalty; migrasi aditif dan tidak mengubah buku poin yang ada.
    if (oldVersion < 28) {
      await db.execute('''
        CREATE TABLE loyalty_rewards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          reward_type TEXT NOT NULL DEFAULT 'gift',
          points_cost INTEGER NOT NULL CHECK(points_cost > 0),
          description TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_loyalty_rewards_active ON loyalty_rewards(is_active, points_cost, name)');
      await db.execute('''
        CREATE TABLE loyalty_redemptions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          reward_id INTEGER,
          reward_name TEXT NOT NULL,
          points_spent INTEGER NOT NULL CHECK(points_spent > 0),
          status TEXT NOT NULL DEFAULT 'completed',
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
          FOREIGN KEY (reward_id) REFERENCES loyalty_rewards(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_loyalty_redemptions_customer ON loyalty_redemptions(customer_id, created_at DESC)');
    }

    // Foto profil pelanggan disimpan opsional sebagai Base64; migrasi aditif.
    if (oldVersion < 25) {
      await db.execute('ALTER TABLE customers ADD COLUMN photo_base64 TEXT');
    }

    // Master kategori produk. Salin kategori teks lama agar tidak hilang.
    if (oldVersion < 24) {
      await db.execute('''
        CREATE TABLE product_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO product_categories (name)
        SELECT DISTINCT TRIM(category) FROM products
        WHERE category IS NOT NULL AND TRIM(category) <> ''
      ''');
      await _seedDefaultProductCategories(db);
    }

    // Riwayat aktivitas pengguna; migrasi aditif dan tidak mengubah transaksi lama.
    if (oldVersion < 21) {
      await db.execute('''
        CREATE TABLE activity_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER,
          user_name TEXT NOT NULL,
          user_role TEXT NOT NULL,
          action TEXT NOT NULL,
          entity_type TEXT,
          entity_id INTEGER,
          description TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_activity_logs_created ON activity_logs(created_at DESC, id DESC)');
      await db.execute('CREATE INDEX idx_activity_logs_user ON activity_logs(user_id, created_at DESC)');
    }
    if (oldVersion < 22) {
      await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT');
    }
    if (oldVersion < 23) {
      await db.execute('''
        CREATE TABLE held_sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          buyer_name TEXT NOT NULL DEFAULT '',
          items_json TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }
        // Akun pengguna dan penugasan mekanik. Migrasi bersifat aditif:
    // data servis lama dipertahankan dan tetap dapat diakses admin/kasir.
    if (oldVersion < 20) {
      await db.execute('''
        CREATE TABLE app_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          display_name TEXT NOT NULL,
          username TEXT NOT NULL COLLATE NOCASE UNIQUE,
          role TEXT NOT NULL CHECK(role IN ('admin', 'cashier', 'mechanic')),
          pin_hash TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT
        )
      ''');
      await db.execute('ALTER TABLE service_orders ADD COLUMN assigned_mechanic_id INTEGER');
      await db.execute('CREATE INDEX idx_service_assigned_mechanic ON service_orders(assigned_mechanic_id, service_status)');
    }
    // Migrasi dari database versi 1 ke versi 2.
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE service_orders
        ADD COLUMN before_photo_path TEXT
      ''');

      await db.execute('''
        ALTER TABLE service_orders
        ADD COLUMN after_photo_path TEXT
      ''');
    }

    // Tambahkan lokasi foto produk tanpa mengubah atau menghapus data lama.
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
    }

    // Riwayat status servis. Backfill satu status awal untuk nota lama
    // tanpa mengubah atau menghapus data transaksi yang sudah ada.
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE service_status_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_order_id INTEGER NOT NULL,
          old_status TEXT,
          new_status TEXT NOT NULL,
          note TEXT,
          changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (service_order_id)
            REFERENCES service_orders(id)
            ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_service_status_history_order
        ON service_status_history(service_order_id, changed_at)
      ''');
      await db.execute('''
        INSERT INTO service_status_history
          (service_order_id, old_status, new_status, note, changed_at)
        SELECT id, NULL, COALESCE(service_status, 'waiting'),
          'Status awal dari data lama', COALESCE(received_at, CURRENT_TIMESTAMP)
        FROM service_orders
      ''');
    }
    // Log pengingat piutang WhatsApp. Migrasi hanya menambah tabel;
    // seluruh data transaksi dan pelanggan lama tetap dipertahankan.
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE receivable_reminder_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          receivable_type TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          phone TEXT NOT NULL,
          opened_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_receivable_reminder_record
        ON receivable_reminder_logs(receivable_type, record_id, opened_at)
      ''');
    }

    // Pembelian, rincian barang, dan pembayaran utang pemasok.
    // Hanya menambah tabel/index; transaksi lama tidak disentuh.
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE purchases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT NOT NULL UNIQUE,
          supplier_id INTEGER,
          subtotal INTEGER NOT NULL DEFAULT 0,
          discount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          paid INTEGER NOT NULL DEFAULT 0,
          payment_status TEXT NOT NULL DEFAULT 'unpaid',
          purchase_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE purchase_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          discount INTEGER NOT NULL DEFAULT 0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE supplier_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          supplier_id INTEGER,
          purchase_id INTEGER,
          amount INTEGER NOT NULL,
          payment_method TEXT,
          payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          notes TEXT,
          FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
          FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_purchases_supplier ON purchases(supplier_id, purchase_date)');
      await db.execute('CREATE INDEX idx_purchase_items_purchase ON purchase_items(purchase_id)');
      await db.execute('CREATE INDEX idx_supplier_payments_purchase ON supplier_payments(purchase_id, payment_date)');
    }

    // Retur pembelian. Migrasi aditif; faktur, pembayaran, dan stok lama tetap utuh.
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE purchase_returns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_id INTEGER NOT NULL,
          return_number TEXT NOT NULL UNIQUE,
          total_amount INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          return_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('''
        CREATE TABLE purchase_return_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_return_id INTEGER NOT NULL,
          purchase_item_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (purchase_return_id) REFERENCES purchase_returns(id) ON DELETE CASCADE,
          FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_purchase_returns_purchase ON purchase_returns(purchase_id, return_date)');
      await db.execute('CREATE INDEX idx_purchase_return_items_return ON purchase_return_items(purchase_return_id)');
    }

    // Penyelesaian retur: kredit untuk mengurangi utang atau pengembalian uang yang diterima.
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE purchases ADD COLUMN return_credit INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE purchase_returns ADD COLUMN credit_applied INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE purchase_returns ADD COLUMN refund_received INTEGER NOT NULL DEFAULT 0");
    }

    // Metode harga pokok dan pelacakan biaya persediaan per batch.
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE inventory_cost_batches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          purchase_id INTEGER,
          purchase_item_id INTEGER,
          batch_code TEXT,
          quantity_received INTEGER NOT NULL,
          quantity_remaining INTEGER NOT NULL,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          notes TEXT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
          FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL,
          FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_inventory_cost_batches_product ON inventory_cost_batches(product_id, received_at, id)');
      await db.execute('''
        CREATE TABLE sale_batch_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          sale_item_id INTEGER NOT NULL,
          batch_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          unit_cost INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
          FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE CASCADE,
          FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_sale_batch_allocations_sale ON sale_batch_allocations(sale_id, sale_item_id)');
      // Stok yang sudah ada dicatat sebagai batch saldo awal agar dapat
      // dipakai metode per batch tanpa mengubah kuantitas stok saat ini.
      await db.execute('''
        INSERT INTO inventory_cost_batches
          (product_id, batch_code, quantity_received, quantity_remaining, unit_cost, received_at, notes)
        SELECT id, 'OPENING-' || id, stock, stock, purchase_price,
          COALESCE(created_at, CURRENT_TIMESTAMP), 'Saldo stok sebelum fitur batch'
        FROM products
        WHERE track_stock = 1 AND stock > 0
      ''');
    }

    // Status pembatalan dan ledger batch untuk retur pembelian.
    if (oldVersion < 11) {
      await db.execute("ALTER TABLE purchases ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
      await db.execute('ALTER TABLE purchases ADD COLUMN cancelled_at TEXT');
      await db.execute('ALTER TABLE purchases ADD COLUMN cancel_reason TEXT');
      await db.execute("ALTER TABLE purchase_returns ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
      await db.execute('ALTER TABLE purchase_returns ADD COLUMN cancelled_at TEXT');
      await db.execute('ALTER TABLE purchase_returns ADD COLUMN cancel_reason TEXT');
      await db.execute('''
        CREATE TABLE purchase_return_batch_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_id INTEGER NOT NULL,
          return_item_id INTEGER NOT NULL,
          batch_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          unit_cost INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (return_id) REFERENCES purchase_returns(id) ON DELETE RESTRICT,
          FOREIGN KEY (return_item_id) REFERENCES purchase_return_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_purchase_return_batch_alloc_return ON purchase_return_batch_allocations(return_id, return_item_id)');
    }

    // Buku pemakaian kredit retur lintas faktur pemasok.
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE supplier_return_credit_applications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_id INTEGER NOT NULL,
          purchase_id INTEGER NOT NULL,
          supplier_id INTEGER NOT NULL,
          amount INTEGER NOT NULL CHECK(amount > 0),
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (return_id) REFERENCES purchase_returns(id) ON DELETE RESTRICT,
          FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE RESTRICT,
          FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_return_credit_applications_return ON supplier_return_credit_applications(return_id, created_at)');
      await db.execute('CREATE INDEX idx_return_credit_applications_purchase ON supplier_return_credit_applications(purchase_id, created_at)');
      await db.execute('''
        INSERT INTO supplier_return_credit_applications
          (return_id, purchase_id, supplier_id, amount, created_at)
        SELECT pr.id, p.id, p.supplier_id, pr.credit_applied,
          COALESCE(pr.created_at, CURRENT_TIMESTAMP)
        FROM purchase_returns pr
        JOIN purchases p ON p.id = pr.purchase_id
        WHERE pr.credit_applied > 0 AND p.supplier_id IS NOT NULL
      ''');
    }

    // Master jasa ditambahkan secara aditif pada database lama.
    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE service_catalog (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category TEXT,
          description TEXT,
          standard_price INTEGER NOT NULL DEFAULT 0 CHECK(standard_price >= 0),
          is_active INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_service_catalog_active ON service_catalog(is_active, sort_order, name)');
      await db.execute('''
        CREATE TABLE service_price_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_id INTEGER NOT NULL,
          old_price INTEGER NOT NULL,
          new_price INTEGER NOT NULL,
          change_reason TEXT,
          changed_by TEXT NOT NULL DEFAULT 'Admin',
          changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (service_id) REFERENCES service_catalog(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_service_price_history_service ON service_price_history(service_id, changed_at)');
      await db.insert('app_settings', {'setting_key': 'service_price_mode', 'setting_value': 'both'});
    }

    // Isi master jasa contoh untuk database lama yang belum memiliki daftar jasa.
    // Tidak menimpa jasa yang sudah dibuat atau diubah oleh pengguna.
    if (oldVersion < 13) {
      await _seedDefaultServiceCatalog(db);
    }

    // Retur penjualan: catatan retur, item retur, dan pengembalian batch FIFO.
    // Migrasi bersifat aditif dan tidak mengubah transaksi lama.
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE sale_returns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          return_number TEXT NOT NULL UNIQUE,
          total_amount INTEGER NOT NULL DEFAULT 0 CHECK(total_amount >= 0),
          refunded_amount INTEGER NOT NULL DEFAULT 0 CHECK(refunded_amount >= 0),
          notes TEXT,
          return_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('''
        CREATE TABLE sale_return_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_return_id INTEGER NOT NULL,
          sale_item_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          unit_price INTEGER NOT NULL DEFAULT 0,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (sale_return_id) REFERENCES sale_returns(id) ON DELETE RESTRICT,
          FOREIGN KEY (sale_item_id) REFERENCES sale_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE sale_return_batch_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_return_item_id INTEGER NOT NULL,
          batch_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          unit_cost INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (sale_return_item_id) REFERENCES sale_return_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_sale_returns_sale ON sale_returns(sale_id, return_date, id)');
      await db.execute('CREATE INDEX idx_sale_return_items_return ON sale_return_items(sale_return_id)');
      await db.execute('CREATE INDEX idx_sale_return_items_sale_item ON sale_return_items(sale_item_id)');
      await db.execute('CREATE INDEX idx_sale_return_batch_alloc_item ON sale_return_batch_allocations(sale_return_item_id)');
    }

    // Biaya langsung servis terpisah dari harga yang ditagihkan ke pelanggan.
    // Migrasi hanya menambah kolom; seluruh nota servis lama tetap dipertahankan.
    if (oldVersion < 16) {
      await db.execute('ALTER TABLE service_orders ADD COLUMN direct_parts_cost INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE service_orders ADD COLUMN other_direct_cost INTEGER NOT NULL DEFAULT 0');
    }

    // Riwayat perubahan biaya modal servis. Migrasi aditif, tanpa mengubah nota lama.
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE service_direct_cost_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_order_id INTEGER NOT NULL,
          old_direct_parts_cost INTEGER NOT NULL DEFAULT 0,
          new_direct_parts_cost INTEGER NOT NULL DEFAULT 0,
          old_other_direct_cost INTEGER NOT NULL DEFAULT 0,
          new_other_direct_cost INTEGER NOT NULL DEFAULT 0,
          changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_service_direct_cost_history_order ON service_direct_cost_history(service_order_id, changed_at, id)');
    }

    // Catat biaya awal pada nota lama yang belum memiliki riwayat biaya.
    // Migrasi hanya menambah baris audit; nilai nota dan transaksi kas tidak diubah.
    if (oldVersion < 18) {
      await db.execute('''
        INSERT INTO service_direct_cost_history (
          service_order_id,
          old_direct_parts_cost,
          new_direct_parts_cost,
          old_other_direct_cost,
          new_other_direct_cost,
          changed_at
        )
        SELECT
          s.id,
          0,
          COALESCE(s.direct_parts_cost, 0),
          0,
          COALESCE(s.other_direct_cost, 0),
          COALESCE(s.received_at, CURRENT_TIMESTAMP)
        FROM service_orders s
        WHERE NOT EXISTS (
          SELECT 1 FROM service_direct_cost_history h
          WHERE h.service_order_id = s.id
        )
      ''');
    }

    // Identitas pelanggan umum disimpan langsung pada nota servis,
    // sehingga tidak membuat record pelanggan/sepeda sementara.
    if (oldVersion < 29) {
      await db.execute("ALTER TABLE service_orders ADD COLUMN customer_name TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN customer_phone TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN bicycle_brand TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN bicycle_model TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN bicycle_type TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN bicycle_color TEXT");
      await db.execute("ALTER TABLE service_orders ADD COLUMN bicycle_serial_number TEXT");
    }

    // Arsip snapshot nota. Data transaksi lama tidak diubah atau dihapus.
    if (oldVersion < 19) {
      await db.execute('''
        CREATE TABLE receipt_snapshots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          document_type TEXT NOT NULL,
          source_type TEXT NOT NULL,
          source_id INTEGER NOT NULL,
          document_number TEXT NOT NULL,
          snapshot_json TEXT NOT NULL,
          issued_at TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await db.execute('CREATE INDEX idx_receipt_snapshots_source ON receipt_snapshots(source_type, source_id, issued_at, id)');
    }

    // Stok opname: menambah tabel sesi dan snapshot produk secara aditif.
    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE stock_opname_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          opname_number TEXT NOT NULL UNIQUE,
          status TEXT NOT NULL DEFAULT 'draft',
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          applied_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE stock_opname_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          sku TEXT,
          unit TEXT NOT NULL DEFAULT 'pcs',
          system_quantity INTEGER NOT NULL DEFAULT 0,
          counted_quantity INTEGER,
          variance INTEGER,
          counted_at TEXT,
          FOREIGN KEY (session_id) REFERENCES stock_opname_sessions(id) ON DELETE RESTRICT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_stock_opname_items_session ON stock_opname_items(session_id, product_name)');
    }

    // Perubahan estimasi dan usulan sparepart servis. Migrasi aditif.
    if (oldVersion < 31) {
      await db.execute('ALTER TABLE service_order_items ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
      await db.execute('''
        CREATE TABLE service_part_allocations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_order_item_id INTEGER NOT NULL,
          batch_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL CHECK(quantity > 0),
          unit_cost INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (service_order_item_id) REFERENCES service_order_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (batch_id) REFERENCES inventory_cost_batches(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_service_part_allocations_item ON service_part_allocations(service_order_item_id)');
      await db.execute('''
        CREATE TABLE service_part_change_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_order_id INTEGER NOT NULL,
          request_type TEXT NOT NULL CHECK(request_type IN ('add', 'cancel')),
          service_order_item_id INTEGER,
          product_id INTEGER,
          item_name TEXT NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          unit_price INTEGER NOT NULL DEFAULT 0,
          mechanic_note TEXT,
          status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'rejected')),
          proposed_by_id INTEGER,
          proposed_by_name TEXT,
          proposed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          reviewed_by_id INTEGER,
          reviewed_by_name TEXT,
          customer_approved INTEGER NOT NULL DEFAULT 0,
          customer_approval_note TEXT,
          reviewed_at TEXT,
          FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT,
          FOREIGN KEY (service_order_item_id) REFERENCES service_order_items(id) ON DELETE RESTRICT,
          FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_service_part_change_requests_order ON service_part_change_requests(service_order_id, status, proposed_at)');
      await db.execute('''
        CREATE TABLE service_estimate_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          service_order_id INTEGER NOT NULL,
          old_estimated_cost INTEGER NOT NULL DEFAULT 0,
          new_estimated_cost INTEGER NOT NULL DEFAULT 0,
          old_labor_cost INTEGER NOT NULL DEFAULT 0,
          new_labor_cost INTEGER NOT NULL DEFAULT 0,
          old_parts_cost INTEGER NOT NULL DEFAULT 0,
          new_parts_cost INTEGER NOT NULL DEFAULT 0,
          old_discount INTEGER NOT NULL DEFAULT 0,
          new_discount INTEGER NOT NULL DEFAULT 0,
          old_total_cost INTEGER NOT NULL DEFAULT 0,
          new_total_cost INTEGER NOT NULL DEFAULT 0,
          reason TEXT,
          customer_approved INTEGER NOT NULL DEFAULT 0,
          customer_approval_note TEXT,
          changed_by_id INTEGER,
          changed_by_name TEXT,
          changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_service_estimate_history_order ON service_estimate_history(service_order_id, changed_at, id)');
    }

    // Buku saldo deposit pelanggan dan buku tip terpisah. Migrasi aditif.
    if (oldVersion < 32) {
      await db.execute('''
        CREATE TABLE customer_wallet_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          entry_type TEXT NOT NULL CHECK(entry_type IN ('deposit', 'service_payment', 'sale_payment', 'refund', 'adjustment')),
          amount INTEGER NOT NULL CHECK(amount > 0),
          balance_after INTEGER NOT NULL CHECK(balance_after >= 0),
          description TEXT,
          reference_type TEXT,
          reference_id INTEGER,
          payment_method TEXT,
          created_by_id INTEGER,
          created_by_name TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('CREATE INDEX idx_customer_wallet_customer ON customer_wallet_ledger(customer_id, created_at DESC, id DESC)');
      await db.execute('CREATE INDEX idx_customer_wallet_reference ON customer_wallet_ledger(reference_type, reference_id)');
      await db.execute('''
        CREATE TABLE tip_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount INTEGER NOT NULL CHECK(amount > 0),
          source_type TEXT NOT NULL CHECK(source_type IN ('service_order', 'sale', 'manual')),
          source_id INTEGER,
          recipient_account_id INTEGER,
          recipient_name TEXT,
          payment_method TEXT,
          status TEXT NOT NULL DEFAULT 'held' CHECK(status IN ('held', 'handed_over', 'cancelled')),
          note TEXT,
          received_by_id INTEGER,
          received_by_name TEXT,
          received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          handed_over_by_id INTEGER,
          handed_over_by_name TEXT,
          handed_over_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_tip_transactions_date ON tip_transactions(received_at DESC, id DESC)');
      await db.execute('CREATE INDEX idx_tip_transactions_source ON tip_transactions(source_type, source_id)');
    }

        // Antrian servis harian: nomor dimulai kembali dari 1 setiap tanggal.
    if (oldVersion < 30) {
      await db.execute('ALTER TABLE service_orders ADD COLUMN queue_number INTEGER');
      await db.execute('ALTER TABLE service_orders ADD COLUMN queue_date TEXT');
      await db.execute('ALTER TABLE service_orders ADD COLUMN queue_priority INTEGER NOT NULL DEFAULT 0');
      await db.execute('CREATE UNIQUE INDEX idx_service_daily_queue ON service_orders(queue_date, queue_number) WHERE queue_number IS NOT NULL');
      await db.execute('CREATE INDEX idx_service_queue_order ON service_orders(queue_date, queue_priority DESC, queue_number ASC)');
    }

  }


  Future<void> _seedDefaultProductCategories(DatabaseExecutor db) async {
    const categories = <String>[
      'Sparepart',
      'Aksesori',
      'Ban dan Velg',
      'Oli dan Pelumas',
      'Peralatan',
      'Lainnya',
    ];
    for (final name in categories) {
      await db.insert(
        'product_categories',
        {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _seedDefaultServiceCatalog(DatabaseExecutor db) async {
    final existing = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM service_catalog'),
        ) ??
        0;
    if (existing > 0) return;

    const services = <Map<String, Object>>[
      {'name': 'Tambal ban dalam', 'category': 'Ban', 'description': 'Tambal kebocoran ban dalam', 'standard_price': 10000, 'sort_order': 10},
      {'name': 'Ganti ban dalam', 'category': 'Ban', 'description': 'Penggantian ban dalam', 'standard_price': 15000, 'sort_order': 20},
      {'name': 'Pasang ban luar', 'category': 'Ban', 'description': 'Pemasangan ban luar', 'standard_price': 15000, 'sort_order': 30},
      {'name': 'Setel velg ringan', 'category': 'Roda', 'description': 'Penyetelan kelurusan velg ringan', 'standard_price': 20000, 'sort_order': 40},
      {'name': 'Setel velg berat', 'category': 'Roda', 'description': 'Penyetelan velg dengan ketidakseimbangan lebih berat', 'standard_price': 35000, 'sort_order': 50},
      {'name': 'Ganti jari-jari', 'category': 'Roda', 'description': 'Jasa penggantian jari-jari; komponen dihitung terpisah', 'standard_price': 25000, 'sort_order': 60},
      {'name': 'Bongkar pasang roda', 'category': 'Roda', 'description': 'Jasa bongkar dan pasang roda', 'standard_price': 10000, 'sort_order': 70},
      {'name': 'Cat rangka sepeda', 'category': 'Pengecatan', 'description': 'Jasa pengecatan rangka; bahan dan tingkat pengerjaan disesuaikan', 'standard_price': 150000, 'sort_order': 80},
      {'name': 'Cat velg', 'category': 'Pengecatan', 'description': 'Jasa pengecatan velg', 'standard_price': 50000, 'sort_order': 90},
      {'name': 'Cat garpu depan', 'category': 'Pengecatan', 'description': 'Jasa pengecatan garpu depan', 'standard_price': 40000, 'sort_order': 100},
      {'name': 'Setel rem', 'category': 'Rem', 'description': 'Penyetelan rem depan atau belakang', 'standard_price': 15000, 'sort_order': 110},
      {'name': 'Ganti kampas rem', 'category': 'Rem', 'description': 'Jasa pemasangan kampas rem; komponen dihitung terpisah', 'standard_price': 15000, 'sort_order': 120},
      {'name': 'Setel operan gigi', 'category': 'Transmisi', 'description': 'Penyetelan perpindahan gigi', 'standard_price': 20000, 'sort_order': 130},
      {'name': 'Cuci sepeda', 'category': 'Perawatan', 'description': 'Jasa pencucian sepeda', 'standard_price': 25000, 'sort_order': 140},
      {'name': 'Servis ringan', 'category': 'Perawatan', 'description': 'Pemeriksaan dan penyetelan ringan', 'standard_price': 35000, 'sort_order': 150},
      {'name': 'Servis lengkap', 'category': 'Perawatan', 'description': 'Pemeriksaan dan perawatan menyeluruh', 'standard_price': 75000, 'sort_order': 160},
    ];

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final service in services) {
      batch.insert('service_catalog', {
        ...service,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }

    _database = null;
  }
}
