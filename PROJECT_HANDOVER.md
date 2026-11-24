# BengkelKu POS — Project Handover

> Dokumen ini adalah catatan induk untuk melanjutkan pengembangan BengkelKu ketika berpindah percakapan atau setelah riwayat chat lama dihapus. Perbarui setiap kali ada keputusan penting, perubahan arsitektur, hasil audit, atau perubahan status pengujian.

**Terakhir diperbarui:** 24 November 2026  
**Repository:** https://github.com/harmanibike/bengkelku  
**Branch kerja:** `main`  
**Jenis aplikasi:** Flutter Android POS, offline-first  
**Bahasa dokumentasi/komunikasi:** Indonesia

---

## 1. Aturan kerja proyek

1. Pertahankan pendekatan **offline-first**. POS lokal harus tetap berfungsi tanpa server atau internet.
2. Prioritaskan pemeriksaan dan perbaikan masalah nyata. Jangan menambah fitur atau mengubah alur yang sudah disepakati tanpa alasan dan persetujuan.
3. Jangan menyatakan fitur selesai hanya karena kode atau UI tersedia. Bedakan status implementasi, automated test, CI, dan pengujian fisik di perangkat.
4. Setiap perubahan kode harus diperiksa dengan formatter, analyzer, test yang relevan, dan CI.
5. Jangan mengaktifkan endpoint pairing, autentikasi token, atau transaksi jaringan sebelum transport dan kontrol keamanan siap.
6. Laporkan progres sebagai **estimasi**, bukan hasil pengukuran objektif. Sertakan pekerjaan yang masih menghalangi kesiapan.
7. Pertahankan kompatibilitas database dan lakukan migrasi secara aditif. Jangan menghapus data transaksi yang sudah ada.
8. Bila ada temuan audit yang ternyata bukan bug, dokumentasikan koreksinya dan jangan melakukan perubahan kode yang tidak diperlukan.

## 2. Status proyek terakhir

Angka berikut adalah estimasi pada 24 November 2026, bukan hasil sertifikasi atau pengujian produksi.

| Area | Estimasi | Keterangan |
|---|---:|---|
| POS Local | **90%** | Ambang untuk mulai mengerjakan Server–Client sudah tercapai; audit dan stabilisasi Local tetap berjalan. |
| Server–Client | **12%** | Fondasi awal tersedia, tetapi belum siap dipakai untuk pertukaran transaksi antarperangkat. |

**Kebijakan tahap:** pengembangan Server–Client boleh berjalan setelah kesiapan Local mencapai 90%, sementara audit POS Local diteruskan secara paralel. Jangan menunggu Local 100% untuk mulai merancang Server–Client, tetapi jangan mengorbankan kestabilan Local.

**Pengujian perangkat fisik:** masih perlu dilakukan dan tidak boleh dianggap lulus hanya berdasarkan CI.

## 3. Repository dan titik kerja terakhir

- Repository: `harmanibike/bengkelku`
- Branch: `main`
- HEAD terakhir yang tercatat: `8d53ebefe7bb35da9ca8ad283669b20b9dafdb27`
- Commit terakhir yang tercatat: `8d53ebef` — `test: cover persistent pairing rate limits`
- Commit terkait sebelumnya:
  - `c23e8751` — `feat: persist device pairing rate limits`
  - `6abe3388` — `feat: add persistent pairing attempt limiter`

Sebelum melanjutkan, periksa HEAD aktual di GitHub karena branch mungkin sudah berubah setelah dokumen ini diperbarui.

## 4. Status CI terakhir yang diketahui

Workflow: **Build BengkelKu POS APK**  
Run ID: `45327364795`  
Commit: `8d53ebef`  
URL: https://github.com/harmanibike/bengkelku/actions/runs/45327364795

Status pada pemeriksaan terakhir: **in_progress** (belum ada kesimpulan sukses/gagal yang terkonfirmasi). Jangan menyebut commit ini lolos CI sampai status run diperiksa ulang.

Tahapan workflow yang terlihat mencakup:
- Setup Flutter dan dependensi
- Generate platform Android bila belum tersedia
- Format dan analyze
- Pengujian SQLite FFI
- Build signed Android APK
- Verifikasi tanda tangan APK
- Upload artifact

CI sebelumnya, run `45319070937` pada commit `0c026158`, tercatat berhasil untuk tahapan tersebut. Itu bukan bukti bahwa commit setelahnya juga berhasil.

**Langkah berikutnya:** periksa run `45327364795`. Jika gagal, ambil log job dan perbaiki hanya penyebab kegagalan yang terverifikasi. Setelah perbaikan, jalankan CI ulang.

## 5. Fondasi Server–Client yang sudah tercatat

### 5.1 Pairing repository

File: `lib/features/settings/data/device_pairing_repository.dart`

Fondasi yang sudah tercatat:
- Pembuatan kode pairing dibatasi untuk Admin.
- Masa berlaku default kode 3 menit; validasi masa berlaku lebih dari 0 dan maksimal 10 menit.
- Kode pairing terdiri dari 10 digit dan disimpan sebagai hash SHA-256, bukan kode mentah.
- Kode kedaluwarsa atau sudah digunakan dibersihkan/ditangani saat proses pairing.
- Pairing mengonsumsi kode secara atomik dan membuat catatan perangkat.
- Token perangkat mentah hanya dikembalikan sekali saat pairing; yang disimpan adalah hash SHA-256.
- Autentikasi perangkat memeriksa token dan status pencabutan serta memperbarui `last_seen_at`.
- Daftar perangkat dan pencabutan perangkat dibatasi untuk Admin.

**Batasan:** fondasi repository bukan berarti endpoint pairing sudah tersedia atau aman untuk jaringan.

### 5.2 Server API dan client

- `local_api_server.dart`: endpoint yang tercatat hanya GET `/api/v1/health`, port 8765, bind ke `anyIPv4`.
- `client_connection_service.dart`: memeriksa health dan kompatibilitas versi.
- Mode Server/Client pada UI masih dinonaktifkan.
- `device_mode_repository.dart`: mode non-local belum dapat disimpan; aplikasi kembali ke Local. Konfigurasi Client dibatasi Admin dan divalidasi.

Server sebaiknya tetap health-only sampai keamanan transport dan autentikasi benar-benar siap.

### 5.3 Persistent pairing rate limiter

Perubahan terakhir yang tercatat:
- File: `lib/features/settings/data/device_pairing_rate_limiter.dart`
- Database: `lib/core/database/app_database.dart`, versi 35
- Test: `test/features/settings/device_pairing_rate_limiter_test.dart`

Desain yang tercatat:
- Maksimal 5 kegagalan dalam jendela 15 menit.
- Lockout 15 menit setelah ambang kegagalan tercapai.
- Status tersimpan di database sehingga bertahan setelah instance limiter dibuat ulang.
- Counter dapat dihapus setelah pairing sukses.
- Alamat IP divalidasi dan dinormalisasi.
- Migrasi database versi 35 menambahkan tabel `device_pairing_attempt_limits` dan indeks secara aditif.

Test yang ditulis mencakup lockout setelah lima kegagalan, persistensi, pembukaan setelah 16 menit, isolasi alamat, reset setelah sukses, dan penolakan alamat tidak valid. **Hasil CI untuk test pada HEAD terakhir belum terkonfirmasi** saat dokumen ini dibuat.

Catatan integrasi:
- Endpoint harus memanggil pemeriksaan izin sebelum memproses pairing.
- Catat hanya kegagalan exchange yang benar-benar gagal; hapus counter setelah sukses.
- Jangan mempercayai `X-Forwarded-For` dari klien LAN secara langsung.
- Pembatasan IP saja tidak cukup untuk mencegah serangan terdistribusi; pertimbangkan kontrol tambahan saat endpoint dirancang.
- Jangan mencatat kode pairing, token mentah, atau rahasia ke log.
- Berikan respons gagal yang generik; jangan membocorkan apakah kode tertentu valid atau tidak.

## 6. Persyaratan keamanan sebelum endpoint jaringan diaktifkan

Sebelum token atau data transaksi melewati jaringan, rancang dan uji setidaknya:

- Transport terenkripsi dan tervalidasi, misalnya TLS dengan strategi identitas/pinning sertifikat yang sesuai untuk LAN.
- Autentikasi token per perangkat dan pemeriksaan status revoke pada setiap permintaan yang relevan.
- Otorisasi berdasarkan peran dan izin endpoint.
- Validasi skema, ukuran body, tipe data, dan batas input.
- Perlindungan replay dan idempotensi untuk operasi yang dapat mengubah transaksi.
- Penanganan konflik sinkronisasi serta aturan sumber data yang jelas.
- Audit log tanpa menyimpan token/kode rahasia.
- Error generik yang tidak membocorkan informasi sensitif.
- Batas percobaan, expiry, rotasi/pencabutan kredensial, dan pengujian penyalahgunaan.
- Uji koneksi putus, retry, duplikasi permintaan, perubahan alamat IP, dan pemulihan.

Jangan menganggap HTTP biasa aman untuk pertukaran token atau transaksi hanya karena jaringan berada di LAN. Verifikasi konfigurasi Android dan workflow aktual sebelum membuat klaim tentang izin cleartext.

## 7. Area audit POS Local berikutnya

Lanjutkan audit dengan fokus pada risiko data dan alur uang. Periksa kode aktual sebelum menyimpulkan ada bug.

Prioritas yang tercatat:
1. Rekonsiliasi Buku Kas untuk pembayaran awal, pelunasan, pembayaran melalui saldo pelanggan, refund, dan transaksi yang dibatalkan.
2. Alur retur/refund dan konsistensi dampaknya terhadap stok, kas, laporan, serta riwayat transaksi.
3. Backup dan restore: kompatibilitas lintas versi skema, validasi file, pemulihan setelah gagal, dan perlindungan agar backup tidak menimpa database secara setengah jadi.
4. Hak akses Admin, Kasir, dan Mekanik pada tindakan sensitif.
5. Integritas database, migrasi, dan transaksi atomik.
6. Uji perangkat Android nyata: alur transaksi, printer, berbagi nota, backup/restore, serta kondisi offline.

### Koreksi temuan sebelumnya

Pernah muncul dugaan ketidaksesuaian pembayaran awal pada layanan. Setelah memeriksa `service_repository.dart`, ditemukan bahwa `addPayment()` memperbarui `down_payment` secara kumulatif dan menghitung `remaining_payment` dari total dikurangi jumlah terbayar. Riwayat pembayaran mengambil catatan dari `cash_transactions` dan `customer_wallet_ledger`. Dugaan tersebut **bukan bug yang terkonfirmasi**; tidak dilakukan perubahan kode untuk dugaan itu.

## 8. Keputusan produk yang harus dipertahankan

### 8.1 Peran pengguna
Peran yang digunakan: **Admin, Kasir, dan Mekanik**. Hak akses harus diperiksa di lapisan logika/data, bukan hanya menyembunyikan tombol di UI.

### 8.2 Printer
Berlaku untuk semua merek dan model printer yang didukung, bukan hanya satu model:
- Admin dan Kasir boleh membuka pengaturan printer dasar.
- Admin dan Kasir boleh menghubungkan printer, memilih printer utama, melakukan tes cetak, dan mencetak struk.
- Hanya Admin yang boleh mengubah pengaturan lanjutan printer.

### 8.3 Menu Pengaturan
- **Harga Jasa** dan **Harga Beli** tetap menjadi menu terpisah di area/menu utama sebelumnya.
- Jangan memindahkan keduanya ke Pengaturan untuk saat ini.
- Pengaturan ditujukan untuk konfigurasi aplikasi seperti printer, metode pembayaran, pengaturan struk/dokumen, poin, hak akses, dan pengaturan terkait.
- **Profil Usaha** tetap berada di dalam Pengaturan.

### 8.4 Pembayaran lebih dan saldo pelanggan
- Jika pelanggan membayar melebihi jumlah yang harus dibayar, sisa pembayaran memiliki dua pilihan: dicatat sebagai **tip** atau masuk ke **saldo pelanggan**.
- Uang titipan/pembayaran di muka pelanggan otomatis masuk ke saldo pelanggan.
- Saldo pelanggan digunakan untuk pembayaran saat transaksi selesai.
- Saldo pelanggan dapat ditarik sesuai alur yang disediakan aplikasi.
- Pastikan setiap perpindahan saldo memiliki catatan ledger dan tidak menggandakan pemasukan kas.

### 8.5 Nota WhatsApp
Saat membagikan nota melalui WhatsApp, pengguna diberi pilihan format **foto atau PDF**.

## 9. Checklist sebelum menyatakan siap

### POS Local
- [ ] CI terbaru lulus.
- [ ] Seluruh test relevan lulus.
- [ ] Tidak ada temuan kritis/high yang belum ditangani.
- [ ] Alur kas, saldo pelanggan, pembayaran, refund, dan retur direkonsiliasi.
- [ ] Backup dan restore diuji pada database dari versi sebelumnya.
- [ ] Hak akses Admin/Kasir/Mekanik diuji.
- [ ] Printer dan nota diuji pada perangkat/printer nyata.
- [ ] Alur offline dan pemulihan setelah aplikasi tertutup diuji.
- [ ] Uji fisik Android selesai dan hasilnya dicatat.

### Server–Client
- [ ] Kontrak API dan versi protokol ditetapkan.
- [ ] Transport aman sudah diterapkan dan diuji.
- [ ] Pairing code expiry, one-time use, rate limit, dan revoke diuji.
- [ ] Autentikasi dan otorisasi setiap endpoint diterapkan.
- [ ] Idempotensi, konflik, retry, dan sinkronisasi transaksi diuji.
- [ ] Backup/pemulihan dan pemulihan koneksi diuji.
- [ ] Uji multi-device pada jaringan lokal nyata selesai.
- [ ] Endpoint transaksi tidak dibuka sebelum seluruh kontrol keamanan wajib terpenuhi.

## 10. Urutan kerja berikutnya

1. Periksa HEAD branch `main` dan status CI run `45327364795`.
2. Jika CI gagal, analisis log dan perbaiki penyebab yang terbukti saja.
3. Verifikasi konfigurasi Android/network dari file workflow dan sumber konfigurasi aktual; jangan mengandalkan asumsi.
4. Teruskan audit POS Local, mulai dari rekonsiliasi kas/refund/retur dan backup-restore.
5. Rancang keamanan transport dan kontrak API Server–Client tanpa mengaktifkan endpoint sensitif terlalu dini.
6. Perbarui dokumen ini setelah ada hasil yang terverifikasi.

---

## 11. Cara melanjutkan di percakapan baru

Salin pesan berikut saat memulai percakapan baru:

> Lanjutkan proyek BengkelKu POS dari repository https://github.com/harmanibike/bengkelku, branch main. Baca PROJECT_HANDOVER.md terlebih dahulu dan verifikasi kondisi repository serta CI terbaru sebelum mengubah kode. Pertahankan keputusan produk dan aturan kerja di dokumen tersebut. Fokus hanya pada masalah yang benar-benar terbukti, laporkan progres sebagai estimasi, dan jangan mengklaim test atau fitur lulus tanpa hasil verifikasi.

**Catatan:** dokumen ini adalah ringkasan operasional, bukan pengganti source code, commit Git, test, atau pemeriksaan ulang kondisi terbaru repository.


## 12. Hasil pemeriksaan lanjutan — 24 November 2026

### CI dan branch
- Run `45327364795` selesai dengan **success** pada commit kode `8d53ebef`.
- Semua step job `Build Signed Android APK` berhasil, termasuk format, analyze, test, build release, verifikasi signature, dan upload artifact.
- Branch `main` kemudian bergerak ke commit dokumentasi `ae74964f` untuk penambahan dokumen handover. Perubahan tersebut tidak mengubah kode aplikasi.

### Batas keamanan jaringan Android
Pemeriksaan workflow `.github/workflows/build-apk.yml` menemukan bahwa workflow menghasilkan AndroidManifest dengan `android:usesCleartextTraffic="true"` pada tingkat aplikasi. Client saat ini memang memanggil health-check melalui HTTP dan server bind ke `anyIPv4`.

- Saat ini endpoint server hanya health-check GET; tidak ada endpoint transaksi atau pengiriman token pada server tersebut.
- Ini tetap merupakan izin cleartext yang luas untuk aplikasi, bukan pembatasan hanya ke endpoint health-check.
- Jangan menambahkan pertukaran pairing code, token, atau data transaksi melalui HTTP biasa.
- Sebelum endpoint sensitif dibuat, rancang transport terenkripsi dan konfigurasi Android yang lebih ketat. Jangan menghapus izin cleartext secara membabi buta sebelum health-check lokal dipindahkan/dirancang ulang, karena koneksi Client saat ini memakai skema HTTP.
- Temuan ini dicatat sebagai **batas keamanan yang harus diselesaikan sebelum Server–Client dipakai untuk data sensitif**, bukan sebagai alasan untuk membuka endpoint baru sekarang.

### Backup dan restore — hasil review statis awal
File yang ditinjau: `lib/core/database/database_backup_service.dart`.

Hal positif yang terlihat:
- Backup dan restore dibatasi untuk Admin.
- Backup memeriksa `PRAGMA integrity_check`, menjalankan WAL checkpoint, menutup database sebelum menyalin file, lalu membuka kembali database dalam blok `finally`.
- Restore memvalidasi file kandidat, integritas SQLite, rentang `user_version`, dan keberadaan tabel inti sebelum mengganti database.
- Restore membuat salinan database sebelum pemulihan dan mencoba mengembalikan salinan tersebut bila proses restore gagal.

Batas pemeriksaan:
- Peninjauan ini bersifat statis; belum ada uji perangkat/restore aktual yang dijalankan dalam sesi ini.
- Pencarian tree repository tidak menemukan test khusus untuk `DatabaseBackupService` / skenario backup-restore.
- Karena itu, backup-restore **belum boleh dinyatakan teruji penuh**. Prioritaskan test untuk backup database aktif, restore versi lama yang harus termigrasi, file rusak/tidak valid, skema yang tidak lengkap, kegagalan saat penggantian file, dan rollback ke salinan pengaman.
- Periksa juga keberadaan file SQLite sidecar (`-wal` / `-shm`) pada skenario perangkat nyata; pastikan proses close/checkpoint benar-benar membuat salinan konsisten.

### Status setelah pemeriksaan
- Tidak ada perubahan kode aplikasi yang dilakukan berdasarkan review statis ini.
- Estimasi progres tetap: POS Local **90%**, Server–Client **12%**.
- Penghambat utama yang dicatat: uji backup-restore khusus belum tersedia/terkonfirmasi; transport cleartext global harus diselesaikan sebelum fitur jaringan sensitif diaktifkan.
