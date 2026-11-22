import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'bengkelku_pos.db';
  static const int _databaseVersion = 9;

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
        complaint TEXT,
        diagnosis TEXT,
        service_status TEXT NOT NULL DEFAULT 'waiting',
        estimated_cost INTEGER NOT NULL DEFAULT 0,
        labor_cost INTEGER NOT NULL DEFAULT 0,
        parts_cost INTEGER NOT NULL DEFAULT 0,
        discount INTEGER NOT NULL DEFAULT 0,
        total_cost INTEGER NOT NULL DEFAULT 0,
        down_payment INTEGER NOT NULL DEFAULT 0,
        remaining_payment INTEGER NOT NULL DEFAULT 0,
        mechanic_name TEXT,
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
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id)
          ON DELETE CASCADE,
        FOREIGN KEY (product_id)
          REFERENCES products(id)
          ON DELETE SET NULL
      )
    ''');

    // Transaksi penjualan.
    batch.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
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
        transaction_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

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
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
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
    }


  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }

    _database = null;
  }
}
