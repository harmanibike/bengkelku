# Arsitektur Multi-Perangkat BengkelKu POS

## Tujuan

Menambahkan operasi beberapa perangkat melalui Wi-Fi/LAN tanpa membuat aplikasi kedua dan tanpa menghilangkan mode offline satu perangkat yang sudah berjalan.

## Prinsip wajib

1. Hanya ada satu aplikasi Android: BengkelKu POS. APK yang sama dipasang pada HP server dan semua perangkat client.
2. Mode Lokal tetap menjadi mode bawaan dan tetap bekerja tanpa jaringan.
3. Mode Server menjadikan HP/tablet Android sebagai pusat data sekaligus terminal operasional penuh.
4. HP Server tetap dapat login sebagai Admin, Kasir, atau peran lain sesuai hak akses dan tetap dapat melakukan transaksi.
5. Proses server tidak boleh bergantung pada sesi akun UI. Logout, login ulang, atau pergantian akun tidak boleh menghentikan layanan server.
6. Mode Client menggunakan data pusat melalui API. Client tidak boleh membuka atau berbagi file SQLite server secara langsung.
7. Database lokal yang sudah ada dipertahankan. Perubahan skema harus berupa migrasi tambahan yang aman dan kompatibel.
8. Tidak boleh mengaktifkan sinkronisasi tulis offline multi-perangkat sebelum strategi konflik dan idempotensi siap.

## Mode perangkat

- **Lokal**: satu perangkat menggunakan database lokal seperti perilaku aplikasi saat ini.
- **Server**: perangkat menjalankan layanan LAN dan tetap menampilkan seluruh fitur aplikasi sesuai hak akses akun yang login.
- **Client**: perangkat terhubung ke satu Server melalui Wi-Fi dan mengakses data pusat.

Semua mode memakai kode aplikasi, layar, modul, dan sistem akun yang sama.

## Arsitektur data dan komunikasi

- SQLite pada perangkat Server menjadi sumber data utama saat mode Server aktif.
- Client mengakses data melalui REST API lokal.
- WebSocket dipakai untuk pemberitahuan perubahan langsung, misalnya transaksi baru, perubahan stok, dan perubahan status servis.
- Client tidak pernah mengakses file database server melalui file sharing.
- Setiap permintaan tulis membawa ID permintaan unik agar percobaan ulang jaringan tidak membuat transaksi ganda.
- Perubahan transaksi yang memengaruhi stok, pembayaran, dan kas harus dijalankan secara atomik.
- Otorisasi peran diperiksa di sisi server, bukan hanya dengan menyembunyikan tombol di UI.

## Identitas perangkat dan pairing

- Perangkat Client dipasangkan dengan Server melalui QR dan persetujuan Admin.
- Server menyimpan daftar perangkat tepercaya dan menyediakan pencabutan akses.
- Token perangkat disimpan secara aman dan dapat diperbarui/dicabut.
- QR hanya untuk proses pairing awal; koneksi berikutnya menggunakan identitas perangkat tersimpan dan mekanisme penemuan/alamat server yang dapat dipulihkan ketika IP berubah.
- Koneksi dibatasi pada jaringan lokal yang dipilih pengguna.

## Sesi akun pada banyak perangkat

- Satu akun pengguna hanya boleh memiliki satu sesi aktif pada satu waktu secara default.
- Login akun yang sama pada perangkat lain ditolak dengan informasi perangkat yang sedang memakai akun tersebut.
- Admin dapat mengakhiri sesi lama dan mengizinkan login pada perangkat baru.
- Sesi memakai heartbeat dan batas kedaluwarsa agar perangkat mati atau terputus tidak mengunci akun selamanya.
- Sesi akun dipisahkan dari lifecycle server. Logout tidak menghentikan layanan server.

## Perilaku saat koneksi terputus

- HP Server tetap dapat bekerja pada database lokalnya.
- Client menampilkan status terputus dan tidak boleh menganggap transaksi tulis berhasil.
- Client tidak boleh diam-diam membuat transaksi lokal yang otomatis digabung ke server.
- Penulisan pada client baru diizinkan lagi setelah koneksi dan otorisasi server terverifikasi.
- Retry permintaan transaksi harus memakai ID permintaan yang sama untuk mencegah duplikasi.

## Siklus implementasi

### Tahap 1 — Fondasi Server Android
- Mode Lokal/Server/Client dan penyimpanan pilihan mode.
- Pengelola lifecycle server yang terpisah dari AuthSession.
- Layanan server Android dengan notifikasi foreground yang jelas.
- Status server, alamat LAN, dan kontrol mulai/berhenti.
- Mode Lokal dan database lama tetap tidak berubah.

### Tahap 2 — Client dan pairing
- Layar sambungkan Client ke Server.
- QR pairing, persetujuan Admin, daftar perangkat, dan pencabutan akses.
- Pemulihan koneksi ketika alamat jaringan berubah.

### Tahap 3 — API dan hak akses
- REST API untuk modul aplikasi.
- Autentikasi token perangkat dan akun.
- Pemeriksaan hak akses di server untuk Admin, Kasir, dan Mekanik.

### Tahap 4 — Sinkronisasi aman
- WebSocket untuk notifikasi perubahan.
- ID permintaan unik dan transaksi atomik.
- Penanganan retry, koneksi putus, dan pencegahan transaksi ganda.

### Tahap 5 — Pengujian
- Dua atau lebih perangkat pada jaringan yang sama.
- Server tetap hidup setelah logout/pergantian akun.
- Server ditutup paksa lalu dinyalakan kembali.
- Wi-Fi terputus ketika transaksi berlangsung.
- Login akun sama pada dua perangkat.
- Stok, kas, pembayaran, dan riwayat diverifikasi tidak ganda atau hilang.

## Batasan implementasi

Dokumen ini adalah spesifikasi desain, bukan klaim bahwa fitur Server–Client telah tersedia. Fitur baru hanya dinyatakan selesai setelah kode, build CI, dan pengujian yang relevan diverifikasi. Build CI tidak menggantikan pengujian perangkat Android fisik.
