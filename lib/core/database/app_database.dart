import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'bengkelku_pos.db';
  static const int _databaseVersion = 2;

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
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }

    _database = null;
  }
}
