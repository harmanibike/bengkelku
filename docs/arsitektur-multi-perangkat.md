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
- Layanan server Android dengan notifikasi foreground yang jelas. Implementasi awal memakai layanan foreground bertipe connectedDevice; layanan hanya dimulai atas tindakan Admin dan tidak auto-start saat boot.
- Listener health-check berjalan pada isolate layanan. Isolate ini belum membuka SQLite dan belum menerima transaksi bisnis.
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

## Skenario kerja bersamaan yang wajib didukung

Server dan Client bukan perangkat dengan tugas yang dikunci secara permanen. Keduanya menjalankan aplikasi dan modul yang sama; fitur yang dapat dipakai ditentukan oleh akun serta hak akses.

Contoh penggunaan serentak:
- HP 1 menjalankan Mode Server dan login sebagai Kasir. Kasir dapat membuat transaksi penjualan seperti biasa.
- HP 2 menjalankan Mode Client dan login sebagai Admin. Admin dapat menambah/mengubah produk, menerima pembelian atau menambah stok, mengelola pelanggan, serta membuka laporan sesuai hak akses.
- Ketika HP 1 menjual barang, stok pusat berkurang satu kali dan perubahan terlihat di HP 2.
- Ketika HP 2 menambah stok, stok pusat bertambah satu kali dan perubahan terlihat di HP 1.
- Laporan pada kedua perangkat membaca data pusat yang sama, sehingga rekap mencerminkan transaksi dan perubahan stok terbaru.

Persyaratan teknis:
1. Semua operasi tulis dari Server maupun Client melewati lapisan repository/use-case yang konsisten dan, pada Mode Server–Client, perubahan Client dikirim ke API Server.
2. Server menjalankan validasi hak akses dan validasi stok terakhir sebelum menyimpan perubahan.
3. Operasi yang saling memengaruhi stok, kas, pembayaran, pembelian, dan penjualan disimpan atomik.
4. Client menerima pemberitahuan perubahan melalui WebSocket; bila koneksi notifikasi terputus, Client melakukan refresh terkontrol saat tersambung kembali.
5. UI menampilkan status koneksi dan waktu pembaruan data. UI tidak boleh menampilkan perubahan seolah tersimpan di pusat sebelum Server mengonfirmasi.
6. Konflik pada data yang sama harus ditolak atau diminta dimuat ulang; jangan menimpa perubahan terbaru secara diam-diam.
7. Perangkat tidak dibatasi hanya sebagai kasir atau hanya sebagai pengelola stok. Pengguna tetap dapat berpindah modul sesuai izin akunnya.

## Urutan teknis Tahap 1 yang lebih rinci

1. Audit titik akses database dan repository untuk memastikan pemilihan sumber data dapat dilakukan tanpa mengubah perilaku Mode Lokal.
2. Tambahkan konfigurasi mode perangkat yang persisten: Lokal, Server, atau Client. Nilai awal tetap Lokal.
3. Tambahkan abstraksi status dan lifecycle Server yang terpisah dari AuthSession; pergantian akun tidak menghentikan layanan.
4. Implementasikan layanan Android yang sesuai dengan batasan lifecycle/background Android, termasuk notifikasi foreground dan penanganan stop/start yang eksplisit.
5. Tampilkan status, alamat LAN, dan kontrol layanan di Pengaturan untuk Admin.
6. Uji Mode Lokal dengan database lama sebelum melanjutkan ke pairing dan API.

Tahap 1 belum dianggap selesai hanya karena pilihan mode tampil. Server baru dinyatakan siap setelah lifecycle layanan Android dan keberlangsungan database lolos pengujian pada perangkat fisik.

## Keputusan keamanan transport LAN (sebelum pairing jaringan)

### Ancaman yang harus ditangani
- Perangkat lain di Wi-Fi yang sama dapat mencoba menyamar sebagai Server.
- Penyerang pada jaringan lokal dapat membaca atau mengubah kode pairing, token, dan data transaksi jika dikirim melalui HTTP biasa.
- IP Server dapat berubah karena DHCP; identitas Server tidak boleh hanya bergantung pada alamat IP.
- Token perangkat yang sudah dicabut tidak boleh tetap diterima oleh endpoint yang masih aktif.

### Rancangan koneksi aman
1. Endpoint HTTP saat ini tetap health-check non-sensitif saja. Tidak boleh menerima kode pairing, token, kredensial akun, atau data bisnis.
2. Pairing dan seluruh API bisnis wajib menggunakan HTTPS melalui `HttpServer.bindSecure` dengan sertifikat dan private key yang dibuat khusus untuk instalasi Server.
3. Identitas Server diverifikasi Client dengan pin sertifikat SHA-256 yang diperoleh melalui QR pairing yang ditampilkan langsung pada perangkat Server. QR juga memuat alamat/port LAN dan kode pairing sekali pakai yang singkat masa berlakunya.
4. Client harus memverifikasi pin sebelum mengirim kode pairing. Dilarang memakai callback yang selalu menerima sertifikat tidak valid (`badCertificateCallback => true`).
5. Pin sertifikat disimpan bersama identitas Server yang dipasangkan. Perubahan sertifikat dianggap perubahan identitas dan memerlukan pairing ulang yang disetujui Admin.
6. Private key tidak boleh masuk ke QR, log, backup publik, atau respons API. Penyimpanan private key harus terlindungi oleh penyimpanan privat aplikasi dan kunci perlindungan perangkat; jangan menyimpan PEM mentah tanpa perlindungan.
7. Pairing code hanya boleh ditukar sekali, memiliki batas percobaan, dan token perangkat hanya dikembalikan sekali. Server hanya menyimpan hash token; semua endpoint terautentikasi wajib memeriksa status pencabutan token.
8. QR pairing tidak boleh menjadi pengganti persetujuan Admin. Admin membuat kode dari sesi Admin aktif dan harus dapat melihat serta mencabut perangkat yang berhasil dipasangkan.

### Kompatibilitas perangkat lama
- BengkelKu menargetkan perangkat Sunmi V2 yang dapat memakai Android 6/7. Pilihan pustaka TLS/pinning wajib diuji pada API level Android 23 dan 24, bukan hanya Android terbaru.
- Paket pinning yang hanya mendukung Android API 24+ tidak boleh dijadikan satu-satunya jalur verifikasi karena Android 6 dapat berada pada API 23.
- Implementasi awal perlu menguji fingerprint sertifikat leaf secara eksplisit di `HttpClient` pada perangkat API 23, termasuk kegagalan saat pin salah, sertifikat berubah, dan masa berlaku sertifikat habis.
- TLS harus menolak koneksi yang tidak cocok; tidak boleh ada fallback diam-diam ke HTTP untuk pairing atau transaksi.

### Isolasi layanan dan akses database
- Listener saat ini berjalan di isolate foreground service, sedangkan sesi Admin dan database UI dibuka pada isolate utama.
- Isolate tidak berbagi memori atau singleton dengan isolate lain. Endpoint pairing tidak boleh langsung mengasumsikan `AppDatabase.instance` pada isolate layanan adalah koneksi database utama.
- Sebelum endpoint pairing/API bisnis dibuat, tentukan satu jalur akses database yang aman: layanan database khusus dengan koneksi SQLite yang dibuka dan dikelola secara eksplisit, atau jembatan pesan terverifikasi ke isolate utama. Semua operasi tulis tetap harus atomik.
- Uji lifecycle database saat UI logout, berpindah akun, masuk background, dan saat service dihentikan. Listener jaringan tidak boleh membuat koneksi database ganda yang tidak terkendali.

### Gerbang sebelum fitur diaktifkan
- Tes TLS dan pinning pada Android 6/API 23 serta Android 7/API 24.
- Tes sertifikat palsu, pin salah, rotasi sertifikat, dan QR kedaluwarsa.
- Tes pairing bersamaan dengan kode yang sama: hanya satu Client boleh berhasil.
- Tes pencabutan token saat Client masih tersambung.
- Audit log agar kode, token, private key, dan data sensitif tidak tercetak.
- Sampai seluruh tes tersebut lulus, Mode Server/Client dan transaksi jaringan tetap nonaktif.

## Catatan evaluasi transport TLS — 25 November 2026

Evaluasi pustaka dilakukan sebelum menambahkan dependensi atau membuka endpoint pairing.

### Temuan

- `dart:io HttpServer.bindSecure` memang mendukung HTTPS, tetapi membutuhkan `SecurityContext` yang sudah memuat certificate chain dan private key. Artinya aplikasi tetap harus memiliki proses penerbitan, penyimpanan, pemuatan, dan rotasi sertifikat yang aman.
- Paket `x509` yang ditemukan berfokus pada parsing/pekerjaan dengan sertifikat X.509; dokumentasinya tidak membuktikan alur lengkap penerbitan sertifikat self-signed untuk kebutuhan ini.
- Paket `ftp_server` menyediakan generator sertifikat self-signed, tetapi produk utamanya adalah server FTP/FTPS, bukan REST API. Matriks kompatibilitas yang ditampilkan menguji macOS, Linux, dan Windows; belum menjadi bukti dukungan Android API 23/24. Jangan menambahkan paket ini hanya untuk mengambil generator sertifikatnya.
- Paket `rk_pki` menyediakan penerbitan/validasi identitas berbasis native Rust dan mencantumkan Android termasuk ABI `armeabi-v7a`, `arm64-v8a`, dan `x86_64`. Namun paket ini masih baru dan bukan implementasi HTTP/TLS server; ia mengelola PKI/identitas yang harus diintegrasikan dengan transport. Dokumentasi paket yang tersedia belum membuktikan pengujian pada Android 6/API 23 dan Android 7/API 24 milik perangkat sasaran.

### Keputusan sementara

Belum menambahkan dependensi TLS/PKI ke `pubspec.yaml`. Tidak ada kandidat yang boleh dianggap aman hanya dari klaim dukungan platform atau contoh penggunaan. Paket native yang baru juga tidak boleh langsung menjadi ketergantungan produksi sebelum build dan uji perangkat sasaran.

Sebelum keputusan final, buat proof-of-concept terisolasi yang membuktikan seluruh hal berikut:

1. Sertifikat dan private key dibuat sekali pada Server, disimpan di direktori privat aplikasi, tidak pernah masuk backup umum/log/QR, dan tetap dapat dimuat setelah aplikasi dimulai ulang.
2. Server dapat menjalankan HTTPS melalui `HttpServer.bindSecure` di isolate foreground yang sekarang digunakan.
3. Client dapat memverifikasi identitas sertifikat yang diperoleh melalui proses pairing lokal, menolak pin yang salah, sertifikat yang diganti, sertifikat kedaluwarsa, dan koneksi tanpa TLS.
4. Pengujian dilakukan pada Android API 23 dan 24 serta ABI perangkat Sunmi yang benar-benar digunakan.
5. Mekanisme rotasi sertifikat dan pairing ulang dirancang agar perubahan sertifikat tidak diterima diam-diam.
6. Private key tidak dikirim ke Client; QR hanya memuat informasi publik/fingerprint dan kode pairing sekali pakai.

### Pekerjaan yang tetap diblokir

- Jangan menambahkan endpoint pairing atau endpoint transaksi ke listener HTTP saat ini.
- Jangan mengirim kode pairing, token, kredensial, atau data bisnis melalui HTTP.
- Jangan mengubah `badCertificateCallback` menjadi selalu menerima sertifikat.
- Jangan membuka database dari task isolate. Jalur komunikasi terverifikasi ke pemilik database atau arsitektur database isolate khusus harus diputuskan dan diuji lebih dahulu.
- Jangan mengaktifkan mode Server/Client di UI sebelum transport, pairing, otorisasi, dan akses database melewati gerbang pengujian.

Catatan ini merupakan hasil evaluasi dokumentasi dan kode, bukan hasil uji TLS pada perangkat fisik.

## Evaluasi lanjutan kandidat penerbit sertifikat — 25 November 2026

Pemeriksaan API paket memperjelas bahwa dua kandidat yang sebelumnya ditinjau belum dapat dipakai langsung sebagai solusi produksi.

### `rk_pki` 0.4.0

- Metadata pub.dev mensyaratkan Dart SDK minimal 3.8, sedangkan batas SDK yang dinyatakan proyek saat ini adalah `>=3.5.0`. Workflow menggunakan Flutter stable tanpa pin versi, sehingga versi SDK build aktual perlu dicatat sebelum mempertimbangkan upgrade batas SDK proyek.
- Paket ini dirancang untuk identitas mesin dan mutual TLS pada transport yang mengintegrasikannya, bukan sebagai server HTTPS umum.
- Kunci privat identitas mesin tetap berada di native library dan tidak diekspor. Satu pengecualian adalah `serverCredential(CertProfile.browserFacing)`, yang mengembalikan sertifikat leaf beserta private key untuk kebutuhan terminasi TLS WebTransport. Profil tersebut berumur tujuh hari dan ditujukan ke loopback, bukan alamat LAN Server Bike POS.
- Karena `HttpServer.bindSecure` membutuhkan certificate chain dan private key yang dapat dimuat ke `SecurityContext`, paket ini tidak menyediakan jalur yang tepat untuk sertifikat server LAN yang dibutuhkan sekarang tanpa mengubah arsitektur transport.
- Kesimpulan: jangan tambahkan `rk_pki` sebagai dependensi untuk listener REST HTTPS saat ini. Evaluasi ulang hanya jika arsitektur transport beralih ke implementasi yang memang terintegrasi dengan PKI tersebut.

Referensi: [rk_pki di pub.dev](https://pub.dev/packages/rk_pki).

### `ftp_server` 2.4.0 — generator sertifikat

- API `SelfSignedCertificate.generate` membuat sertifikat ECDSA P-256 dan mengekspos `certificatePem`, `privateKeyPem`, serta fingerprint SHA-256. Sertifikat yang sudah dibuat dapat dimuat kembali melalui konstruktornya.
- API generator yang didokumentasikan menerima `commonName`, `dnsNames`, dan masa berlaku; tidak menyediakan parameter `ipAddresses` untuk Subject Alternative Name bertipe IP.
- Client Bike POS direncanakan terhubung ke alamat IP LAN yang dapat berubah. Mengisi alamat IP sebagai DNS SAN bukan pengganti IP SAN. Karena itu sertifikat dari generator ini belum memenuhi rancangan verifikasi hostname/IP secara normal untuk koneksi ke alamat IP.
- Dokumentasi paket menyatakan generator dapat digunakan di Android/iOS, tetapi matriks CI yang dipublikasikan untuk paket FTP menyebut macOS, Linux, dan Windows. Klaim tersebut belum membuktikan pengujian generator pada Android API 23/24 dan ABI Sunmi sasaran.
- Paket FTP tidak perlu dimasukkan ke aplikasi hanya untuk mengambil generator sertifikat. Jika source generator dipertimbangkan untuk diadaptasi, audit implementasi kriptografi, dependency, SAN, lisensi, dan pengujian Android tetap wajib dilakukan terlebih dahulu.

Referensi: [API SelfSignedCertificate](https://pub.dev/documentation/ftp_server/latest/self_signed_certificate/SelfSignedCertificate-class.html), [dokumentasi ftp_server](https://pub.dev/packages/ftp_server).

### Keputusan setelah pemeriksaan API

Belum ada kandidat yang lolos untuk diintegrasikan ke aplikasi utama. Jangan mengubah `pubspec.yaml`, jangan menambahkan endpoint HTTPS/pairing, dan jangan mengaktifkan Mode Client. Langkah teknis berikutnya adalah membuat proof-of-concept sertifikat dengan SAN IP yang benar dan siklus penyimpanan private key yang terlindungi, lalu menjalankannya pada Android API 23/24. Bila tidak ada generator Dart murni yang memenuhi kebutuhan tersebut, evaluasi opsi native Android/Java atau transport TLS yang terintegrasi dengan PKI sebelum memilih dependensi.

## Rancangan PoC TLS berikutnya — identitas DNS stabil dan rute IP LAN

Pemeriksaan source paket dan API Dart menghasilkan jalur PoC yang lebih menjanjikan daripada membuat sertifikat dengan IP SAN dinamis.

### Temuan generator sertifikat

- `basic_utils` 5.8.2 menyediakan `X509Utils.generateSelfSignedCertificate`, parameter SAN, KeyUsage, dan ExtendedKeyUsage; metadata pub.dev mencantumkan Android sebagai platform.
- Audit source `X509Utils.generateSelfSignedCertificate` menunjukkan setiap nilai `sans` saat ini dienkode dengan tag ASN.1 `0x82` (dNSName). Artinya nilai IP yang diberikan sebagai SAN tidak akan menjadi iPAddress SAN yang benar.
- Jangan gunakan IP literal pada parameter SAN paket tersebut dan jangan menganggap sertifikatnya memiliki IP SAN.
- Namun, generator ini dapat menjadi kandidat untuk sertifikat dengan satu nama DNS logis yang stabil, jika uji sertifikat membuktikan ekstensi DNS SAN, EKU serverAuth, masa berlaku, dan signature valid.

### Pola identitas yang akan diuji

1. Saat Server pertama kali disiapkan, buat ID acak permanen untuk instalasi tersebut, misalnya identitas DNS sintetis di bawah domain khusus yang tidak dipakai untuk resolusi Internet.
2. Sertifikat Server memuat DNS SAN identitas sintetis itu. Identitas tersebut tidak berubah ketika DHCP mengganti alamat IP Server.
3. QR pairing memuat identitas DNS, IP/port LAN saat itu, fingerprint sertifikat, dan kode pairing sekali pakai. QR tidak pernah memuat private key.
4. Client membuat URL HTTPS menggunakan nama DNS sintetis sebagai host URL, sehingga nama itu tetap menjadi identitas TLS/hostname yang diverifikasi.
5. `HttpClient.connectionFactory` diuji untuk membuka plain TCP Socket ke IP LAN yang didapat dari pairing, sementara URL HTTPS tetap menggunakan nama DNS sintetis. Proxy harus dinonaktifkan secara eksplisit untuk jalur lokal ini; factory harus menolak host URL yang tidak cocok dengan identitas Server yang tersimpan.
6. Client memakai `SecurityContext(withTrustedRoots: false)` dengan sertifikat publik Server yang dipasangkan sebagai trust anchor. TLS harus tetap memeriksa signature, masa berlaku, dan kecocokan DNS SAN. Tidak menggunakan `badCertificateCallback`.
7. Perubahan sertifikat atau identitas Server mewajibkan pairing ulang Admin.

Dokumentasi Dart menyatakan `connectionFactory` menerima URL yang diminta dan menghasilkan socket koneksi. Dokumentasi mekanisme pinning yang memakai `dart:io` juga menjelaskan factory HTTPS mengembalikan plain Socket untuk diamankan oleh HttpClient, dan TLS tetap memverifikasi hostname serta masa berlaku. Walau demikian, perilaku ini belum diuji pada versi Dart/Flutter dan Android sasaran proyek; karena itu rancangan ini masih hipotesis PoC, bukan implementasi yang sudah disahkan.

### Penyimpanan private key

- Kandidat awal untuk diuji adalah `flutter_secure_storage` versi 10.x, bukan versi 11.x.
- Dokumentasi versi 10 menyebut dukungan Android mulai API 23; changelog versi 11 menaikkan minimum Android menjadi API 24.
- Versi 10.3.4 perlu dipatok dan diuji bila Android 6/API 23 harus tetap didukung. Jangan memakai rentang versi yang dapat menarik versi 11 secara otomatis.
- Private key PEM hanya boleh disimpan melalui penyimpanan terenkripsi yang memakai Android Keystore; jangan tulis PEM mentah ke file biasa, SharedPreferences biasa, log, atau QR. Pengujian juga harus mencakup uninstall/reinstall, pemulihan backup, dan kegagalan Keystore.
- Ukuran private key/sertifikat dan batas penyimpanan plugin harus diuji. Bila ukuran tidak cocok untuk secure key-value storage, simpan file terenkripsi di direktori privat dan simpan hanya kunci pembungkus di secure storage.

### Batas kompatibilitas Flutter yang ditemukan

- Flutter 3.35 mengubah minimum Android yang didukung template/tooling menjadi API 24 (Android 7).
- Workflow Bike POS saat ini memakai `channel: stable` tanpa pin versi Flutter, dan menghasilkan folder Android dari template SDK yang sedang terpasang. Akibatnya, build yang dibuat dengan Flutter 3.35 atau lebih baru tidak dapat dijanjikan kompatibel dengan Android 6/API 23.
- Android 7/API 24 atau lebih baru menjadi baseline yang masuk akal untuk workflow stable saat ini, tetapi harus diverifikasi pada Sunmi V2 fisik.
- Jika Android 6/API 23 benar-benar wajib, perlu evaluasi pin Flutter ke rilis sebelum 3.35 dan audit seluruh plugin/dependensi agar minSdk, Gradle, dan API Android tidak melampaui 23. Jangan sekadar memaksa `minSdk 23` pada template Flutter 3.35+.

### Gerbang PoC

- Sertifikat DNS SAN sintetis diuji dengan OpenSSL/validator independen: SAN harus bertipe DNS, EKU harus serverAuth, masa berlaku valid, dan private/public key harus cocok.
- Koneksi HTTPS diuji ketika URL memakai nama DNS sintetis tetapi socket diarahkan ke IP LAN.
- Uji harus membuktikan hostname salah ditolak, sertifikat berbeda ditolak, sertifikat kedaluwarsa ditolak, dan HTTP/plaintext ditolak.
- Uji perubahan IP DHCP tanpa mengganti identitas sertifikat.
- Uji pembuatan, penyimpanan, pemuatan ulang, dan penghapusan private key pada Android API 23/24 sesuai baseline perangkat.
- Baru setelah PoC lulus, dependensi boleh dipertimbangkan untuk aplikasi utama. Tidak ada perubahan pada `pubspec.yaml` atau listener produksi pada tahap evaluasi ini.
