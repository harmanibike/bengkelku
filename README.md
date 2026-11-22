# BengkelKu POS

Aplikasi Android untuk mengelola operasional toko spare part dan bengkel servis sepeda. Target akhirnya adalah satu aplikasi yang menangani penjualan, servis, pelanggan, inventaris, pembelian, keuangan, karyawan, laporan, pencetakan, backup, dan sinkronisasi perangkat.

## Roadmap Utama Pengembangan

Dokumen ini menjadi acuan resmi pengembangan BengkelKu POS. Status fitur harus diperbarui berdasarkan implementasi dan pengujian nyata, bukan hanya karena kode sudah ditambahkan.

### Keterangan status

- [x] Fondasi/modul sudah tersedia di aplikasi (tetap perlu audit dan pengujian lanjutan).
- [ ] Belum selesai atau masih menjadi rencana pengembangan.

## 1. Dashboard utama

- [ ] Ringkasan omzet harian, mingguan, dan bulanan.
- [ ] Total transaksi penjualan.
- [ ] Jumlah sepeda yang sedang diservis.
- [ ] Jumlah servis menunggu, dikerjakan, selesai, dan diambil.
- [ ] Ringkasan pemasukan dan pengeluaran.
- [ ] Informasi stok barang menipis.
- [ ] Grafik penjualan dan pendapatan servis.
- [ ] Aktivitas transaksi terbaru.
- [x] Pintasan menu untuk modul inti.
- [ ] Penyempurnaan seluruh kartu ringkasan agar menggunakan data aktual dan periode yang tepat.

## 2. Data pelanggan

- [x] Fondasi data dan daftar pelanggan.
- [ ] Tambah, edit, hapus, dan cari pelanggan secara lengkap.
- [ ] Nama, nomor telepon, dan alamat.
- [ ] Riwayat pembelian pelanggan.
- [ ] Riwayat servis pelanggan.
- [ ] Daftar sepeda milik pelanggan.
- [ ] Catatan khusus pelanggan.
- [ ] Riwayat pembayaran dan piutang.

## 3. Data sepeda

- [x] Fondasi data sepeda pelanggan.
- [ ] Merek dan model sepeda.
- [ ] Jenis sepeda: standar, MTB, BMX, road bike, folding bike, sepeda anak, dan e-bike.
- [ ] Warna dan ukuran frame.
- [ ] Nomor rangka atau serial number.
- [ ] Foto sepeda.
- [ ] Pemilik sepeda dan riwayat kepemilikan.
- [ ] Riwayat servis dan penggantian komponen.
- [ ] Informasi garansi sepeda.

## 4. Manajemen servis bengkel

- [x] Fondasi penerimaan dan daftar servis.
- [x] Pencatatan DP dan pembayaran servis ke transaksi kas.
- [ ] Nomor nota servis otomatis dan konsisten.
- [ ] Keluhan pelanggan, hasil pemeriksaan, dan diagnosis mekanik.
- [ ] Estimasi biaya servis.
- [ ] Biaya jasa mekanik dan biaya spare part.
- [ ] Diskon servis.
- [ ] Pembayaran DP, cicilan, dan pelunasan dengan validasi saldo.
- [ ] Penentuan mekanik dan catatan pengerjaan.
- [ ] Status servis: menunggu, pemeriksaan, sedang dikerjakan, selesai, sudah diambil, dan dibatalkan.
- [ ] Foto sebelum dan sesudah servis.
- [ ] Riwayat perubahan status.
- [ ] Riwayat servis setiap sepeda.
- [ ] Garansi pekerjaan servis.
- [ ] Pencetakan nota servis.

## 5. Kasir penjualan (POS)

- [x] Fondasi kasir, keranjang, pembayaran tunai, dan pencatatan transaksi.
- [x] Pengurangan stok dan pencatatan kas saat transaksi penjualan.
- [ ] Penjualan spare part dan aksesori yang lebih lengkap.
- [ ] Pencarian produk dan pemindaian barcode.
- [ ] Perubahan jumlah barang.
- [ ] Harga eceran dan grosir.
- [ ] Diskon per barang dan diskon seluruh transaksi.
- [ ] Pajak yang dapat dikonfigurasi.
- [ ] Pembayaran transfer, QRIS, dan pembayaran campuran.
- [ ] Pembayaran DP dan pelunasan bila diperlukan.
- [ ] Cetak struk.
- [ ] Simpan transaksi, pembatalan, dan retur penjualan dengan pembalikan stok/kas yang benar.

## 6. Manajemen produk dan inventaris

- [x] Fondasi data produk dan inventaris.
- [x] SKU/barcode, kategori, merek, harga modal, harga jual, dan stok.
- [x] Stok masuk/keluar dan riwayat pergerakan stok.
- [x] Peringatan stok menipis.
- [x] Foto produk: ambil dari kamera atau galeri, simpan offline, dan tampilkan pada daftar produk serta halaman kasir (build release, analisis, tes otomatis, dan verifikasi tanda tangan APK berhasil; uji perangkat fisik tetap diperlukan).
- [ ] Tambah, edit, dan arsip/hapus produk dengan perlindungan riwayat transaksi.
- [ ] Harga jual grosir.
- [ ] Penyesuaian stok dan stok opname.
- [ ] Retur barang.
- [ ] Cetak label harga dan label barcode.

## 7. Pembelian dan pemasok

- [ ] Data pemasok.
- [ ] Nomor faktur pembelian.
- [ ] Pencatatan pembelian barang.
- [ ] Penambahan stok otomatis.
- [ ] Harga beli dan diskon pembelian.
- [ ] Pembayaran pemasok dan utang pembelian.
- [ ] Pelunasan utang.
- [ ] Retur kepada pemasok.
- [ ] Riwayat pembelian per pemasok.

## 8. Keuangan dan kas

- [x] Fondasi transaksi kas masuk dan keluar.
- [x] Pencatatan penerimaan penjualan.
- [x] Pencatatan DP dan pembayaran servis.
- [x] Ringkasan laporan dasar.
- [ ] Pengeluaran operasional dan pembelian barang.
- [ ] Biaya gaji dan komisi.
- [ ] Saldo kas dan rekap harian.
- [ ] Laporan laba dan rugi.
- [ ] Laporan arus kas.
- [ ] Kategori transaksi yang dapat dikelola.
- [ ] Rekonsiliasi transaksi dan koreksi/pembatalan yang memiliki jejak audit.

## 9. Karyawan dan mekanik

- [ ] Data karyawan dan mekanik.
- [ ] Akun pengguna.
- [ ] Hak akses berdasarkan jabatan: admin, kasir, mekanik, dan pengelola stok.
- [ ] Riwayat pekerjaan mekanik.
- [ ] Perhitungan komisi mekanik.
- [ ] Laporan kinerja karyawan.

## 10. Laporan

- [x] Fondasi laporan dan ringkasan transaksi.
- [ ] Laporan penjualan.
- [ ] Laporan servis dan pendapatan servis.
- [ ] Laporan produk terlaris.
- [ ] Laporan stok.
- [ ] Laporan pembelian dan pemasok.
- [ ] Laporan pelanggan.
- [ ] Laporan piutang dan utang.
- [ ] Laporan pemasukan dan pengeluaran.
- [ ] Laporan laba dan rugi.
- [ ] Laporan komisi mekanik.
- [ ] Filter berdasarkan tanggal dan periode.
- [ ] Ekspor laporan ke PDF dan Excel.

## 11. Nota, struk, dan pencetakan

- [ ] Cetak struk kasir dan nota servis.
- [ ] Kertas thermal 58 mm dan 80 mm.
- [ ] Dukungan printer Bluetooth.
- [ ] Simpan nota sebagai PDF atau gambar.
- [ ] Bagikan nota melalui WhatsApp.
- [ ] Cetak label harga dan barcode produk.

## 12. Pengaturan aplikasi

- [ ] Profil toko/bengkel: nama, alamat, logo, dan nomor telepon.
- [ ] Pengaturan pajak dan format mata uang.
- [ ] Pengaturan printer.
- [ ] Pengaturan nomor nota.
- [ ] Pengaturan harga dan diskon.
- [ ] Pengaturan akun pengguna dan hak akses.
- [ ] Backup database.
- [ ] Restore atau impor data.
- [ ] Ekspor data.

## 13. Multi-perangkat dan sinkronisasi

- [ ] Satu HP Android sebagai server utama.
- [ ] HP lain dan tablet sebagai perangkat kasir/pengguna.
- [ ] Koneksi melalui jaringan Wi-Fi/LAN.
- [ ] Sinkronisasi transaksi, stok, pelanggan, dan data servis.
- [ ] REST API untuk komunikasi perangkat.
- [ ] WebSocket untuk pembaruan langsung.
- [ ] Hubungkan perangkat melalui QR Code.
- [ ] Hak akses setiap perangkat dan persetujuan perangkat baru.
- [ ] Pencegahan transaksi ganda.
- [ ] Penanganan konflik data.

## 14. Keamanan dan keandalan

- [x] Database lokal SQLite sebagai fondasi penyimpanan.
- [ ] Pastikan data tetap tersimpan setelah aplikasi ditutup/dibuka kembali.
- [ ] Backup dan pemulihan data yang teruji.
- [ ] Migrasi database tanpa menghapus data lama.
- [ ] Validasi transaksi untuk mencegah pembayaran berlebih.
- [ ] Pencegahan transaksi ganda.
- [ ] Pengamanan akses pengguna.
- [ ] Pencatatan aktivitas penting.
- [ ] Pengujian otomatis sebelum APK dirilis.
- [ ] Verifikasi tanda tangan APK.
- [ ] Pembaruan aplikasi tanpa menghapus aplikasi lama.

## 15. Fitur tambahan

- [ ] Pengingat servis berkala dan garansi servis.
- [ ] Notifikasi stok minimum.
- [ ] Notifikasi servis selesai melalui WhatsApp.
- [ ] Foto bukti transaksi.
- [ ] Kode QR pada nota.
- [ ] Pencarian riwayat servis menggunakan nomor rangka.
- [ ] Program pelanggan loyal, poin, dan voucher.
- [ ] Harga khusus pelanggan grosir.
- [ ] Manajemen beberapa cabang.
- [ ] Sinkronisasi cloud sebagai opsi tambahan.

## Tahapan prioritas pengembangan

Urutan berikut menjadi panduan pengerjaan. Urutan dapat disesuaikan jika audit menemukan masalah kritis pada data atau transaksi.

1. **Stabilitas fitur inti:** dashboard, pelanggan, sepeda, servis, produk, kasir, dan laporan.
2. **Inventaris dan pembelian:** stok opname, pemasok, pembelian, utang, dan retur.
3. **Penyempurnaan servis:** mekanik, diagnosis, biaya jasa/spare part, foto, status, garansi, dan nota.
4. **Keuangan:** saldo kas, pengeluaran, piutang, utang, pembayaran campuran, laba rugi, dan arus kas.
5. **Karyawan dan hak akses:** akun, peran, komisi, dan kinerja.
6. **Laporan lanjutan:** grafik, laporan terperinci, PDF, dan Excel.
7. **Nota dan perangkat:** printer Bluetooth, thermal, PDF, barcode, dan berbagi nota.
8. **Backup dan pengaturan:** profil toko, konfigurasi, backup, restore, dan ekspor.
9. **Multi-perangkat:** server lokal, Wi-Fi/LAN, API, WebSocket, QR Code, dan sinkronisasi.
10. **Fitur lanjutan:** pengingat, loyalitas, voucher, dan multi-cabang.

## Aturan wajib setiap perubahan

1. Periksa kode, struktur database, dan alur transaksi yang sudah ada sebelum mengubahnya.
2. Pertahankan kompatibilitas database lama. Jangan menghapus database atau data pengguna.
3. Jika perubahan skema diperlukan, buat migrasi yang aman, berurutan, dan dapat diuji.
4. Jangan mengubah atau mengganti konfigurasi keystore penandatanganan APK.
5. Transaksi yang saling berkaitan (penjualan, servis, stok, dan kas) harus konsisten dan sebisa mungkin disimpan dalam satu transaksi database.
6. Pembatalan, retur, dan koreksi harus membalik dampak stok/kas secara benar serta menyimpan jejak audit; jangan menghapus riwayat keuangan secara diam-diam.
7. Setiap modul harus diuji sebelum melanjutkan ke modul berikutnya.
8. Sebelum rilis, jalankan format, analisis kode, pengujian, build APK release, dan verifikasi tanda tangan.
9. Jangan menyatakan build atau pengujian berhasil sebelum hasil GitHub Actions benar-benar menunjukkan sukses.
10. Perbarui checklist roadmap ini setelah fitur benar-benar selesai dan terverifikasi.

## Target akhir

BengkelKu POS menjadi satu aplikasi Android yang mampu mengelola kegiatan toko sepeda dan bengkel dari awal sampai akhir: penjualan spare part, penerimaan servis, pengelolaan mekanik, inventaris, pembelian, keuangan, hingga laporan usaha.

**Prinsip utama: fitur yang sudah berjalan tidak boleh rusak ketika fitur baru ditambahkan, dan data lama harus tetap aman.**
