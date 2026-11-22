# BengkelKu POS

Aplikasi Android offline untuk mengelola toko spare part dan bengkel servis sepeda. Roadmap ini menjadi acuan resmi pengembangan dan harus mencerminkan kondisi kode yang benar-benar tersedia.

## Keterangan status

- [x] Implementasi/fondasi fitur sudah tersedia di kode aplikasi.
- [ ] Belum tersedia lengkap, masih perlu implementasi, atau belum terverifikasi.
- Checklist [x] bukan berarti seluruh skenario sudah lulus uji perangkat fisik. Build dan tes otomatis tetap perlu dibedakan dari pengujian langsung di HP.

## 1. Dashboard

- [x] Dashboard dan pintasan ke modul inti.
- [ ] Ringkasan omzet dan transaksi harian, mingguan, bulanan yang tervalidasi.
- [ ] Ringkasan sepeda dalam proses, servis selesai, dan siap diambil.
- [ ] Ringkasan kas masuk/keluar dan saldo kas.
- [ ] Peringatan stok menipis berbasis ambang yang dapat diatur.
- [ ] Grafik dan aktivitas terbaru yang lengkap.

## 2. Pelanggan

- [x] Fondasi penyimpanan dan daftar pelanggan.
- [ ] Tambah, edit, arsip, validasi nomor telepon, dan pencarian pelanggan secara lengkap.
- [ ] Riwayat pembelian dan servis dalam satu profil pelanggan.
- [ ] Daftar sepeda milik pelanggan dan catatan khusus.
- [x] Data pelanggan terhubung dengan transaksi/piutang yang memerlukan identitas pelanggan.
- [x] Daftar piutang penjualan dan servis serta pengingat WhatsApp manual.
- [ ] Riwayat pembayaran terpadu dan ringkasan saldo per pelanggan.

## 3. Data sepeda

- [x] Fondasi data sepeda pelanggan.
- [ ] Merek, model, jenis, warna, ukuran frame, dan nomor rangka.
- [ ] Foto sepeda dan riwayat kepemilikan.
- [ ] Riwayat servis/penggantian komponen per sepeda.
- [ ] Informasi garansi sepeda.

## 4. Servis bengkel

- [x] Fondasi penerimaan servis dan daftar pekerjaan.
- [x] Pencatatan DP, pembayaran bertahap, sisa tagihan, dan penerimaan ke transaksi kas.
- [x] Status servis dan riwayat perubahan status.
- [x] Pelunasan tidak menjadi syarat mutlak untuk mengambil sepeda; sisa tagihan tetap tercatat sebagai piutang.
- [x] Master jasa servis: data contoh awal dapat dipakai, diedit, dinonaktifkan, atau dihapus.
- [x] Pengaturan harga jasa: harga standar otomatis dan perubahan manual.
- [x] Pembatasan perubahan harga manual dengan verifikasi PIN admin.
- [x] Riwayat perubahan harga jasa beserta harga lama/baru, alasan, dan waktu.
- [x] Profil usaha (nama, alamat, telepon, WhatsApp, email, website, nomor pajak, logo, dan catatan bawah nota).
- [x] Identitas usaha ditampilkan pada detail transaksi penjualan dan detail servis.
- [ ] Nomor nota servis dan format nota yang dapat dikonfigurasi.
- [ ] Keluhan, diagnosis, estimasi, foto sebelum/sesudah, dan catatan mekanik yang lengkap.
- [ ] Penentuan mekanik, biaya jasa/spare part, komisi, dan diskon servis.
- [ ] Garansi pekerjaan servis.
- [ ] Cetak atau bagikan nota servis.

## 5. Kasir penjualan (POS)

- [x] Fondasi kasir, keranjang, dan penyimpanan transaksi.
- [x] Pembayaran tunai dan pencatatan uang yang benar-benar diterima.
- [x] Pengurangan stok dan pencatatan pergerakan stok saat penjualan.
- [x] Pembayaran sebagian/tempo dengan pelanggan dan saldo piutang.
- [x] Pelunasan piutang penjualan dicatat sebagai transaksi kas masuk.
- [x] Riwayat penjualan menampilkan status pembayaran dan sisa tagihan.
- [x] Pembatalan transaksi dengan pemulihan stok dan pembalikan penerimaan kas yang tercatat.
- [ ] Barcode scanner, harga grosir, diskon, pajak, transfer, QRIS, dan pembayaran campuran.
- [x] Retur penjualan dengan pembalikan stok, pengembalian dana, penyesuaian piutang, dan jejak audit.
- [ ] Cetak struk dan berbagi bukti transaksi.

## 6. Produk dan inventaris

- [x] Fondasi data produk dan inventaris.
- [x] SKU/barcode, kategori, merek, harga modal, harga jual, dan stok.
- [x] Foto produk dari kamera/galeri, penyimpanan offline, dan tampilan pada daftar produk serta kasir.
- [x] Riwayat pergerakan stok masuk/keluar.
- [x] Halaman Audit Stok dengan pencarian, filter masuk/keluar, sumber transaksi, waktu, dan perubahan stok.
- [x] Peringatan/indikator stok menipis yang tersedia pada modul produk.
- [ ] Arsip produk dan penghapusan aman dengan perlindungan riwayat transaksi.
- [ ] Harga jual grosir dan beberapa tingkat harga.
- [x] Stok opname: snapshot stok, input hitung fisik, validasi perubahan stok selama penghitungan, penerapan selisih, dan audit pergerakan stok.
- [x] Retur penjualan dengan pengembalian stok dan pencatatan retur.
- [ ] Cetak label harga dan barcode.

## 7. Pembelian dan pemasok

- [x] Data pemasok dan halaman detail pemasok.
- [x] Pencatatan faktur pembelian dan item pembelian.
- [x] Penambahan stok serta pencatatan pergerakan stok dari pembelian.
- [x] Harga beli, diskon, pembayaran awal, pembayaran lanjutan, dan saldo utang pemasok.
- [x] Retur pembelian kepada pemasok.
- [x] Pencatatan kredit retur, penerapan kredit ke faktur pemasok lain, dan pengembalian uang tunai secara terpisah.
- [x] Metode pembaruan harga beli: rata-rata tertimbang, harga terakhir, manual, dan per batch (FIFO).
- [x] Riwayat batch biaya dan perlindungan pembatalan pembelian/retur dengan alasan serta validasi dependensi.
- [x] Laporan pembelian dan pemasok dasar.
- [ ] Audit menyeluruh seluruh skenario pembelian lama, stok batch, retur, dan utang pada data nyata.

## 8. Keuangan dan kas

- [x] Fondasi transaksi kas masuk dan keluar.
- [x] Penerimaan penjualan dan pembayaran piutang penjualan.
- [x] DP dan pembayaran servis masuk ke transaksi kas.
- [x] Pengeluaran pembelian dan pembayaran pemasok dicatat pada alur pembelian.
- [x] Buku kas terpadu dengan saldo awal, saldo berjalan, ringkasan masuk/keluar, filter periode/jenis, dan transaksi manual.
- [ ] Kategori pemasukan/pengeluaran yang dapat dikelola.
- [x] Pencatatan manual biaya operasional, gaji, dan komisi sebagai kas keluar; belum ada payroll atau perhitungan komisi otomatis.
- [ ] Rekonsiliasi serta koreksi dengan jejak audit.
- [ ] Laporan arus kas dan laba rugi lengkap yang tervalidasi; saat ini tersedia ringkasan laba kotor barang berdasarkan HPP FIFO/alokasi batch dan harga modal tersimpan untuk transaksi lama.

## 9. Karyawan dan mekanik

- [ ] Data karyawan dan mekanik.
- [ ] Akun pengguna dan autentikasi.
- [ ] Hak akses admin, kasir, mekanik, dan pengelola stok.
- [ ] Riwayat pekerjaan dan komisi mekanik.
- [ ] Laporan kinerja karyawan.

## 10. Laporan

- [x] Fondasi laporan dan ringkasan transaksi.
- [x] Laporan pembelian/pemasok dasar.
- [x] Audit riwayat pergerakan stok.
- [x] Ringkasan piutang servis dan penjualan barang.
- [x] Ringkasan penjualan bersih setelah retur dan laba kotor barang setelah pengurangan HPP barang yang diretur.
- [x] Ringkasan pendapatan servis dari nota berstatus selesai/diambil berdasarkan tanggal penyelesaian.\n- [ ] Laporan servis, produk terlaris, dan stok yang lebih lengkap.
- [ ] Laporan utang/piutang terperinci.
- [ ] Laporan pemasukan, pengeluaran, laba rugi, arus kas, dan komisi.
- [ ] Filter periode yang konsisten dan ekspor PDF/Excel.

## 11. Nota, struk, dan pencetakan

- [ ] Cetak struk kasir dan nota servis.
- [ ] Kertas thermal 58 mm/80 mm dan printer Bluetooth.
- [ ] Simpan nota sebagai PDF atau gambar.
- [ ] Bagikan nota melalui WhatsApp.
- [ ] Cetak label harga dan barcode.

## 12. Pengaturan aplikasi

- [x] Profil usaha dan logo.
- [x] Pengaturan metode update harga beli.
- [x] Pengaturan harga jasa dan PIN admin untuk override harga.
- [ ] Pengaturan pajak, mata uang, nomor nota, printer, diskon, dan akun pengguna.
- [ ] Backup database, restore, dan ekspor data yang telah diuji.

## 13. Multi-perangkat

- [ ] Server lokal, koneksi Wi-Fi/LAN, dan perangkat klien.
- [ ] API/WebSocket, sinkronisasi data, dan penghubung perangkat melalui QR.
- [ ] Pengamanan perangkat baru, pencegahan transaksi ganda, dan resolusi konflik.

## 14. Keamanan dan keandalan

- [x] Database lokal SQLite.
- [x] Migrasi database bertahap sampai skema yang digunakan fitur saat ini; migrasi baru wajib diuji dan tidak boleh menghapus data lama.
- [x] Pengujian otomatis dijalankan pada pipeline CI.
- [x] Pipeline CI memiliki tahap build APK release dan verifikasi tanda tangan.
- [ ] Backup/restore yang teruji pada perangkat.
- [ ] Audit menyeluruh persistensi data setelah aplikasi ditutup/dibuka.
- [ ] Uji perangkat fisik untuk alur utama, printer, kamera, dan berbagi file.
- [ ] Pengamanan akun/hak akses dan pencatatan aktivitas pengguna.

## 15. Pengingat dan fitur tambahan

- [x] Daftar piutang gabungan servis dan penjualan barang.
- [x] Filter/pencarian piutang dan rincian sisa tagihan.
- [x] Membuka WhatsApp dengan template pengingat yang dapat ditinjau pengguna.
- [x] Log mencatat waktu WhatsApp dibuka untuk pengingat; aplikasi tidak mengirim pesan otomatis.
- [ ] Pengingat servis berkala dan garansi.
- [ ] Notifikasi stok minimum yang dapat dikonfigurasi.
- [ ] Loyalitas, poin, voucher, multi-cabang, dan sinkronisasi cloud opsional.

## Urutan pengerjaan berikutnya

Pengerjaan dilakukan satu tahap per satu tahap, dengan pemeriksaan kode dan database sebelum perubahan:

1. Audit dan rapikan dokumentasi/checklist README agar sesuai implementasi.
2. Retur penjualan: desain alur, validasi pembayaran, stok, kas, dan audit.
3. Stok opname: hitung fisik, selisih, persetujuan, dan penyesuaian stok.
4. Keuangan dan laporan: buku kas, saldo, kategori, arus kas, laba rugi, utang/piutang.
5. Nota dan pencetakan: format nota, PDF/gambar, WhatsApp, printer Bluetooth/thermal.
6. Pelanggan, sepeda, mekanik, karyawan, dan hak akses.
7. Backup, restore, ekspor, dan uji pemulihan data.
8. Uji perangkat fisik dan stabilisasi rilis.

## Aturan wajib setiap perubahan

1. Periksa kode, struktur database, dan alur transaksi sebelum mengubahnya.
2. Pertahankan kompatibilitas database lama; jangan menghapus database atau data pengguna.
3. Gunakan migrasi skema yang aman, berurutan, dan dapat diuji.
4. Jangan mengubah atau mengganti konfigurasi keystore/penandatanganan APK.
5. Transaksi yang berkaitan (penjualan, servis, stok, dan kas) harus konsisten dan menggunakan transaksi database bila memungkinkan.
6. Pembatalan, retur, dan koreksi harus membalik dampak stok/kas secara benar serta menyimpan jejak audit.
7. Uji setiap modul sebelum berpindah ke modul berikutnya.
8. Jalankan format, analisis, tes, build APK release, dan verifikasi tanda tangan melalui CI.
9. Jangan menyatakan build atau tes berhasil sebelum hasil CI menunjukkan sukses.
10. Perbarui checklist hanya setelah implementasi dan pemeriksaan yang sesuai.

**Prinsip utama: fitur baru tidak boleh merusak fitur yang sudah berjalan, dan data lama harus tetap aman.**
