# Bike POS

Aplikasi Android offline untuk mengelola toko spare part dan bengkel servis sepeda. Roadmap ini menjadi acuan resmi pengembangan dan harus mencerminkan kondisi kode yang benar-benar tersedia.

## Ringkasan audit kode (24 November 2026)

Audit ini adalah pemeriksaan statis terhadap struktur repository, halaman, repository data, database, dan tes yang tersedia. Status [x] berarti implementasi/fondasi ditemukan di kode, bukan jaminan semua alur telah lulus uji perangkat. Pipeline untuk perubahan antrian terbaru masih berjalan saat README ini diperbarui.

**Sudah memiliki implementasi utama:** transaksi kasir dan stok; servis multi-sparepart dan pembayaran bertahap; pelanggan dan data sepeda; pembelian, pemasok, retur pembelian; piutang servis/penjualan; buku kas dan sebagian pemeriksaan rekonsiliasi; laporan dasar; akun Admin/Kasir/Mekanik; backup/restore lokal; format nota PDF/PNG; pengaturan printer Bluetooth dan tes cetak 58 mm; pengingat stok; loyalty/reward; serta fondasi antrian servis.

**Belum lengkap atau belum terverifikasi:** cetak nota transaksi langsung ke printer thermal, USB/Wi-Fi printer, laci uang fisik, laporan keuangan lengkap dan ekspor, payroll/komisi, pengingat servis/garansi, papan pemanggilan antrian, dan mode server-client multi-perangkat. Seluruh transaksi saat ini tetap offline pada database lokal perangkat.

**Tes otomatis yang ditemukan di repository:** formatter mata uang, generator dokumen nota, transisi status servis, pemeriksaan koneksi client-server, dan widget dasar. Cakupan tes repository/transaksi database masih terbatas; audit fisik pada HP, printer, kamera, dan skenario backup/restore tetap diperlukan.

## Kebijakan kompatibilitas perangkat Android

Keputusan pengguna: aplikasi **tidak dikhususkan untuk merek, model, atau terminal kasir tertentu**. Targetnya adalah sebanyak mungkin perangkat Android yang dapat didukung secara teknis oleh Flutter dan seluruh plugin yang digunakan.

Ketentuan wajib:
- Mendukung berbagai merek dan model HP Android serta tablet; tata letak harus responsif terhadap ukuran layar dan orientasi yang didukung.
- Tidak menjadikan satu perangkat sebagai acuan utama atau syarat kompatibilitas.
- Tetapkan `minSdk` berdasarkan persyaratan plugin dan fitur yang benar-benar digunakan. Jangan menjanjikan dukungan untuk versi Android yang tidak memenuhi persyaratan teknis.
- Uji pada beberapa versi Android dan kelas perangkat yang berbeda, termasuk ukuran layar kecil/besar.
- Kamera, barcode scanner, Bluetooth, USB, jaringan, dan printer harus memeriksa kemampuan serta izin runtime perangkat. Fitur yang tidak didukung harus memberi pesan yang jelas dan tidak boleh membuat aplikasi inti crash.
- Printer thermal harus menggunakan jalur koneksi yang kompatibel dengan perangkat/printer; jangan mengunci aplikasi pada satu merek atau protokol printer.
- Fungsi kasir, servis, inventaris, dan database lokal harus tetap dapat digunakan offline tanpa ketergantungan pada perangkat keras opsional.
- Setiap perubahan kompatibilitas wajib melewati format, analisis, tes otomatis, build APK, dan pengujian pada perangkat fisik yang tersedia.
- Jangan mengubah desain, ukuran, tipografi, atau tata letak nota thermal 58 mm yang sudah disetujui tanpa permintaan eksplisit pengguna.

**Catatan verifikasi:** klaim kompatibilitas harus berdasarkan `minSdk`, persyaratan plugin, hasil build, dan matriks uji perangkat. Build APK yang berhasil bukan bukti bahwa semua merek/model Android telah diuji.

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
- [x] Tambah, edit, dan pencarian pelanggan.
- [ ] Arsip pelanggan dan validasi nomor telepon yang lebih ketat.
- [ ] Riwayat pembelian dan servis dalam satu profil pelanggan.
- [ ] Daftar sepeda milik pelanggan dan catatan khusus.
- [x] Data pelanggan terhubung dengan transaksi/piutang yang memerlukan identitas pelanggan.
- [x] Daftar piutang penjualan dan servis serta pengingat WhatsApp manual.
- [ ] Riwayat pembayaran terpadu dan ringkasan saldo per pelanggan.

## 3. Data sepeda

- [x] Fondasi data sepeda pelanggan.
- [x] Merek, model, jenis, warna, ukuran frame, nomor rangka, dan catatan sepeda.
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
- [x] Biaya modal sparepart dan biaya langsung lain servis dicatat terpisah dari harga jual, serta ditampilkan pada detail nota; input dan koreksi biaya aktual tersedia dari detail nota; riwayat nilai lama/baru dan waktu perubahan tersimpan; tidak mengubah tagihan pelanggan atau mengurangi stok otomatis.
- [x] Nomor nota servis otomatis dan pengaturan tampilan/format dokumen 58/80 mm.
- [x] Keluhan, diagnosis, estimasi biaya, catatan, dan foto sebelum servis.
- [x] Foto sebelum/sesudah dapat disimpan dan dilihat sebagai dokumentasi internal; foto tidak dimasukkan ke nota, PDF/PNG, cetak, atau WhatsApp.
- [ ] Catatan mekanik terstruktur dan foto sesudah pada seluruh alur servis masih perlu audit.
- [x] Penugasan mekanik Admin/Kasir dan saran otomatis mekanik dengan pekerjaan aktif paling sedikit; pilihan manual tetap tersedia.
- [x] Beberapa sparepart dalam satu nota servis, kalkulasi subtotal, validasi stok, dan pengurangan stok secara transaksional.
- [x] Biaya jasa, sparepart, diskon, DP, pembayaran bertahap, dan sisa tagihan.
- [ ] Perhitungan komisi mekanik otomatis.
- [ ] Garansi pekerjaan servis.
- [x] Buat pratinjau nota servis dalam PDF dan foto PNG, serta bagikan melalui menu berbagi Android; pilihan chat WhatsApp dan pengiriman tetap dilakukan manual oleh pengguna.
- [x] Bukti penerimaan sepeda saat masuk bengkel dan bukti pelunasan servis sebagai dokumen terpisah; keduanya memiliki snapshot arsip sendiri. Bukti pelunasan hanya dapat diterbitkan saat sisa tagihan nol.
- [x] Snapshot nota servis yang diterbitkan menyimpan data servis, pembayaran, dan profil usaha; arsip dapat dibuka ulang tanpa membaca ulang data transaksi terkini.


## 4A. Antrian servis dan penugasan mekanik

- [x] Nomor antrian otomatis per tanggal, format A001, A002, dan seterusnya; nomor dimulai kembali dari A001 pada hari berikutnya.
- [x] Nomor antrian dan tanggal disimpan pada nota servis; migrasi database versi 30 menambahkan kolom antrian tanpa menghapus riwayat servis lama.
- [x] Filter daftar servis untuk menampilkan antrian aktif (Menunggu, Pemeriksaan, dan Dikerjakan).
- [x] Urutan daftar antrian berdasarkan prioritas terlebih dahulu, lalu nomor antrian/FIFO.
- [x] Admin dapat memberi atau menghapus tanda prioritas.
- [x] Form penerimaan menyarankan mekanik aktif dengan jumlah pekerjaan aktif paling sedikit; Admin/Kasir dapat memilih mekanik lain secara manual.
- [ ] Tampilan papan antrian khusus/monitor eksternal, pemanggilan nomor, notifikasi pelanggan, estimasi waktu tunggu, dan cetak tiket antrian.
- [ ] Pengujian antrian pada beberapa transaksi serentak dan perangkat fisik.

**Catatan implementasi:** status aktif yang dihitung sebagai beban mekanik adalah Menunggu, Pemeriksaan, dan Dikerjakan. Status Selesai, Diambil, dan Dibatalkan tidak dihitung. Nomor antrian lama sebelum migrasi tidak dibuat ulang secara retroaktif.

## 5. Kasir penjualan (POS)

- [x] Fondasi kasir, keranjang, dan penyimpanan transaksi.
- [x] Pembayaran tunai dan pencatatan uang yang benar-benar diterima.
- [x] Pengurangan stok dan pencatatan pergerakan stok saat penjualan.
- [x] Pembayaran sebagian/tempo dengan pelanggan dan saldo piutang.
- [x] Pelunasan piutang penjualan dicatat sebagai transaksi kas masuk.
- [x] Riwayat penjualan menampilkan status pembayaran dan sisa tagihan.
- [x] Pembatalan transaksi dengan pemulihan stok dan pembalikan penerimaan kas yang tercatat.
- [x] Pilihan metode pembayaran tunai, transfer bank, QRIS, kartu debit, dan kartu kredit; metode aktif dapat diatur dan pilihan dicatat pada transaksi kasir.
- [x] Scan barcode produk menggunakan kamera Android dari halaman Kasir; hasil scan otomatis mencari dan menambahkan produk yang cocok ke keranjang. Pemindaian barcode menggunakan kamera Android yang tersedia; dukungan scanner eksternal mengikuti kemampuan perangkat dan koneksi yang didukung.
- [ ] Integrasi/verifikasi pembayaran digital otomatis, harga grosir, diskon, pajak, dan pembayaran campuran.
- [x] Retur penjualan dengan pembalikan stok, pengembalian dana, penyesuaian piutang, dan jejak audit.
- [x] Buat pratinjau nota penjualan dalam PDF dan foto PNG, termasuk rincian item, pembayaran, retur, dan sisa tagihan; bagikan melalui menu berbagi Android.
- [x] Cetak melalui layanan cetak Android dari pratinjau PDF.
- [x] Snapshot nota penjualan yang diterbitkan menyimpan data transaksi, item, pembayaran, retur, dan profil usaha; arsip dapat dibuka ulang tanpa membaca ulang data transaksi terkini.
- [ ] Uji hasil cetak pada printer fisik untuk kertas 58/80 mm dan seluruh variasi format.

## 6. Produk dan inventaris

- [x] Fondasi data produk dan inventaris.
- [x] SKU/barcode, kategori, merek, harga modal, harga jual, dan stok.
- [x] Pengaturan metode pembaruan harga beli ditempatkan di dalam menu Produk.
- [x] Foto produk dari kamera/galeri, penyimpanan offline, dan tampilan pada daftar produk serta kasir.
- [x] Riwayat pergerakan stok masuk/keluar.
- [x] Halaman Audit Stok dengan pencarian, filter masuk/keluar, sumber transaksi, waktu, dan perubahan stok.
- [x] Peringatan/indikator stok menipis yang tersedia pada modul produk.
- [ ] Arsip produk dan penghapusan aman dengan perlindungan riwayat transaksi.
- [ ] Harga bertingkat per produk: nama tingkat, minimal kuantitas, harga per unit, status aktif/nonaktif, dan pemilihan otomatis di kasir berdasarkan jumlah dalam satu baris.
- [x] Stok opname: snapshot stok, input hitung fisik, validasi perubahan stok selama penghitungan, penerapan selisih, dan audit pergerakan stok.
- [x] Retur penjualan dengan pengembalian stok dan pencatatan retur.
- [ ] Cetak label harga dan barcode.

## 7. Pembelian dan pemasok

- [x] Data pemasok dan halaman detail pemasok.
- [x] Pencatatan faktur pembelian langsung maupun kulakan online, termasuk marketplace/toko, nomor pesanan, resi, diskon, ongkir, packing, asuransi, biaya admin marketplace, transfer, dan biaya lainnya.
- [x] Satu faktur dapat memuat beberapa jenis barang dengan kuantitas dan harga beli masing-masing.
- [x] Faktur baru berstatus menunggu penerimaan; stok tidak bertambah hanya karena faktur disimpan.
- [x] Penerimaan barang sebagian maupun penuh; hanya kuantitas yang benar-benar diterima menambah stok, batch biaya, dan mutasi stok.
- [x] Status penerimaan barang dipisahkan dari status pembayaran faktur.
- [x] Harga beli, pembayaran awal/lanjutan, dan saldo utang pemasok.
- [x] Retur pembelian dibatasi pada jumlah yang telah diterima dikurangi retur aktif sebelumnya.
- [x] Pembatalan pembelian yang diterima sebagian hanya membalik stok yang diterima; pembatalan otomatis ditolak jika batch telah terpakai/berubah, pembayaran belum dibalik, atau retur aktif masih ada.
- [x] Pencatatan kredit retur, penerapan kredit ke faktur pemasok lain, dan pengembalian uang tunai secara terpisah.
- [x] Metode pembaruan harga beli: rata-rata tertimbang, harga terakhir, manual, dan per batch (FIFO).
- [x] Riwayat batch biaya dan perlindungan pembatalan pembelian/retur dengan alasan serta validasi dependensi.
- [x] Laporan pembelian dan pemasok dasar.
- [x] Audit pembulatan HPP per unit dan rekonsiliasi nilai batch terhadap total biaya faktur, termasuk penerimaan bertahap (termasuk penerimaan parsial, batch pecahan biaya, pembatalan, dan uji otomatis).
- [ ] Audit menyeluruh skenario pembelian lama, stok batch, retur, pembayaran, kredit pemasok, dan utang pada data nyata.
- [ ] Uji langsung alur pembelian dan retur pada perangkat Android fisik.

## 8. Keuangan dan kas

- [x] Fondasi transaksi kas masuk dan keluar.
- [x] Penerimaan penjualan dan pembayaran piutang penjualan.
- [x] DP dan pembayaran servis masuk ke transaksi kas.
- [x] Pengeluaran pembelian dan pembayaran pemasok dicatat pada alur pembelian.
- [x] Buku kas terpadu dengan saldo awal, saldo berjalan, ringkasan masuk/keluar, filter periode/jenis, dan transaksi manual.
- [x] Menu Pengeluaran khusus untuk biaya manual dengan filter Hari Ini/Bulan Ini/Semua Waktu, kategori, keterangan, nominal, dan metode Cash atau Transfer Bank (Admin).
- [x] Pengeluaran Cash mengurangi Saldo Toko; Transfer Bank tercatat sebagai transaksi non-tunai dan tidak mengubah saldo fisik laci.
- [x] Saldo Toko adalah saldo uang tunai fisik di laci kasir, bukan omzet, laba, saldo bank, atau seluruh aset bisnis.
- [x] Tanam Modal dan Tarik Modal dicatat manual oleh Admin; metode Cash memengaruhi saldo laci, sedangkan Transfer Bank hanya menjadi catatan non-tunai.
- [x] Penjualan, pembayaran servis, pembelian tunai, refund, dan pengeluaran terkait dicatat otomatis dari transaksi sumber; tidak boleh diinput ulang secara manual.
- [x] QRIS, transfer bank, dan metode non-tunai lain tidak menambah/mengurangi saldo fisik laci. Refund mengikuti metode pembayaran asal.
- [x] Riwayat Saldo Toko memiliki saldo berjalan dan filter Modal Awal, Uang Masuk, Uang Keluar, Penjualan, Refund, Pengeluaran, Pembelian, dan Penyesuaian.
- [ ] Kategori pemasukan/pengeluaran yang dapat dikelola.
- [x] Pencatatan manual biaya operasional, gaji, dan komisi sebagai kas keluar; belum ada payroll atau perhitungan komisi otomatis.
- [x] Ringkasan pengeluaran manual Buku Kas dan sisa laba setelah beban yang tercatat; bukan laba bersih final dan perlu menghindari pencatatan biaya langsung yang sama dua kali.
- [x] Pemeriksaan rekonsiliasi baca-saja untuk referensi transaksi kas, arah/nominal kas, serta selisih riwayat pembayaran pelanggan dan pemasok tersedia di Buku Kas.
- [ ] Koreksi transaksi langsung dari layar rekonsiliasi dengan persetujuan dan jejak audit belum tersedia.
- [ ] Laporan arus kas dan laba rugi lengkap yang tervalidasi; saat ini tersedia ringkasan laba kotor barang berdasarkan HPP FIFO/alokasi batch dan harga modal tersimpan untuk transaksi lama.

## 9. Karyawan dan mekanik

- [x] Akun lokal Admin, Kasir, dan Mekanik dengan login username/PIN.
- [x] Admin dapat membuat, mengubah, dan menonaktifkan akun; akun pertama dibuat sebagai Admin.
- [x] Pembatasan akses dasar: pengelolaan akun oleh Admin; Kasir dapat mengelola transaksi kasir dan servis; Mekanik hanya mengakses pekerjaan yang ditugaskan.
- [x] Riwayat aktivitas akun untuk tindakan yang telah diintegrasikan ke activity log.
- [ ] Data karyawan/HR, pengelola stok sebagai role terpisah, komisi otomatis, dan laporan kinerja.

## 10. Laporan

- [x] Fondasi laporan dan ringkasan transaksi.
- [x] Laporan pembelian/pemasok dasar.
- [x] Audit riwayat pergerakan stok.
- [x] Ringkasan piutang servis dan penjualan barang.
- [x] Ringkasan saldo piutang servis, piutang penjualan setelah retur/refund, dan utang pemasok aktif; posisi berjalan tidak dibatasi periode laporan.
- [x] Ringkasan penjualan bersih setelah retur dan laba kotor barang setelah pengurangan HPP barang yang diretur.
- [x] Ringkasan pendapatan servis dari nota berstatus selesai/diambil berdasarkan tanggal penyelesaian.
- [x] Laba kotor servis dan gabungan laba kotor barang + servis berdasarkan biaya langsung servis yang dicatat manual.
- [x] Sisa setelah beban operasional manual tercatat; pembayaran pembelian pemasok tidak dikurangkan lagi karena HPP dihitung pada saat penjualan.
- [ ] Laporan servis, produk terlaris, dan stok yang lebih lengkap.
- [ ] Laporan utang/piutang terperinci.
- [ ] Laporan laba rugi bersih, biaya operasional teralokasi, payroll/komisi otomatis, dan validasi menyeluruh; saat ini tersedia arus kas serta ringkasan laba kotor barang/servis.
- [ ] Filter periode yang konsisten dan ekspor PDF/Excel.

## Kebijakan laci uang otomatis

- Menu Pengaturan sudah menyediakan sakelar ON/OFF dan menyimpan pilihan secara lokal.
- Laci direncanakan terhubung ke port RJ11/RJ12 pada printer thermal yang memang mendukung cash drawer.
- Perintah ESC/POS untuk tes buka, buka manual, dan buka otomatis setelah pembayaran belum diintegrasikan.
- Karena perintah fisik belum tersedia, sakelar ON/OFF saat ini hanya menyimpan preferensi dan belum membuka laci.
- Dukungan aktual bergantung pada port, pinout, tegangan/pulsa, protokol printer, dan kompatibilitas laci; tidak semua printer mendukung laci.

## Kebijakan tampilan dan format struk

- Pengaturan format 58/80 mm, logo, informasi usaha/pelanggan, catatan transaksi/bawah nota, skala teks, dan kerapatan sudah tersedia dan tersimpan lokal.
- Generator PDF/PNG menggunakan pengaturan tersebut untuk nota penjualan dan servis.
- Hasil cetak fisik 58/80 mm dan konsistensi lintas printer tetap perlu diuji; pengaturan format tidak berarti cetak thermal langsung sudah terintegrasi.

## Kebijakan hak akses printer

Berlaku untuk printer yang didukung oleh integrasi aplikasi:

- Admin dan Kasir dapat mencari/menghubungkan printer Bluetooth, menyimpan printer utama, memutus koneksi, dan menjalankan tes cetak ESC/POS 58 mm.
- Pengaturan printer lanjutan khusus Admin belum tersedia sebagai panel terpisah.
- USB dan Wi-Fi/LAN belum diimplementasikan/terverifikasi.
- Cetak transaksi masih melalui layanan cetak Android dari PDF, bukan koneksi Bluetooth ESC/POS yang tersimpan.
- Sakelar laci uang dan format nota tersedia, tetapi perintah fisik laci belum diimplementasikan.

## 11. Nota, struk, dan pencetakan

- [x] Generate dan pratinjau nota penjualan serta servis dalam format PDF.
- [x] Generate foto PNG dari nota dan tampilkan pratinjau sebelum dibagikan.
- [x] Bagikan file PDF atau foto melalui menu berbagi Android; pengguna memilih WhatsApp/chat dan menekan kirim sendiri.
- [x] Buka layanan cetak Android dari pratinjau PDF.
- [x] Arsip snapshot nota yang pernah diterbitkan dan buka ulang dari riwayat nota per transaksi.
- [x] Bukti penerimaan sepeda saat masuk bengkel dan bukti pelunasan servis sebagai dokumen terpisah; keduanya memiliki snapshot arsip sendiri. Bukti pelunasan hanya dapat diterbitkan saat sisa tagihan nol.
- [x] Cari, hubungkan, simpan/pilih printer Bluetooth, putuskan koneksi, dan tes cetak ESC/POS 58 mm tersedia untuk Admin/Kasir.
- [ ] Cetak nota transaksi langsung melalui printer thermal belum terhubung; transaksi masih dicetak melalui layanan cetak Android dari PDF.
- [ ] Dukungan USB dan Wi-Fi/LAN belum tersedia/terverifikasi; tes 80 mm dan kompatibilitas lintas merek/model belum diverifikasi.
- [x] Menu Pengaturan untuk tampilan dan format struk: 58/80 mm, logo, nama/alamat/kontak usaha, data pelanggan, catatan transaksi, catatan bawah, skala teks, dan kerapatan; pengaturan tersimpan lokal dan diterapkan pada generator PDF/PNG.
- [x] Menu Pengaturan sakelar ON/OFF buka laci otomatis tersimpan lokal.
- [ ] Perintah ESC/POS untuk tes buka, buka manual, dan buka otomatis setelah pembayaran berhasil tersimpan; menunggu integrasi printer langsung dan uji perangkat.
- [ ] Cetak label harga dan barcode.

## 12. Pengaturan aplikasi

- [x] Profil usaha dan logo.
- [x] Pengaturan harga jasa dan PIN admin untuk override harga.
- [x] Pengaturan metode pembayaran yang aktif pada kasir.
- [x] Pengaturan akun pengguna dan hak akses.
- [x] Pengaturan metode pembayaran, profil usaha, harga jasa, format struk, dan opsi pengingat stok/loyalty.
- [x] Penyimpanan printer Bluetooth utama dan tes cetak ESC/POS 58 mm.
- [ ] Pengaturan pajak, mata uang dinamis, dan integrasi perintah laci uang.
- [x] Pengaturan tampilan/format struk dan sakelar otomatis laci uang tersimpan di tabel app_settings.
- [x] Menu backup dan restore database lokal tersedia dengan validasi file dan salinan pengaman sebelum pemulihan.
- [ ] Ekspor data bisnis terpilih (CSV/Excel) dan pengujian pemulihan lintas versi/perangkat.

## 13. Multi-perangkat

### Fondasi yang sudah ada

- [x] Pilihan Mode Perangkat ditampilkan untuk Admin; Mode Lokal tetap menjadi mode aktif dan aman.
- [x] Penyimpanan alamat IP/host dan port Server pada pengaturan lokal perangkat Client.
- [x] Validasi dasar alamat host dan rentang port.
- [x] Pemeriksaan endpoint kesehatan API Client melalui kontrak `GET /api/v1/health`; respons harus mengidentifikasi `bengkelku_pos`, status `ok`, dan API versi 1.
- [x] Tes otomatis untuk respons API valid, endpoint tidak tersedia, aplikasi yang salah, dan versi API yang tidak cocok.

### Belum tersedia / belum boleh dianggap aktif

- [x] Layanan Android foreground menjaga endpoint kesehatan Server tetap aktif selama layanan berjalan; saat ini hanya melayani pemeriksaan LAN, bukan transaksi.
- [x] Fondasi kode pairing numerik sekali pakai dengan masa berlaku terbatas dan pertukaran token perangkat.
- [x] Token perangkat disimpan sebagai hash; fondasi daftar perangkat tepercaya, pencabutan akses, dan pembatasan percobaan pairing tersedia pada lapisan repository.
- [x] Metadata versi APK Server dan Client diambil dari versi rilis `pubspec.yaml` melalui `APP_VERSION` saat build.
- [ ] Integrasi pairing melalui endpoint jaringan, persetujuan/pengikatan perangkat end-to-end, dan pengujian antar-HP.
- [ ] Transport aman (TLS dan verifikasi identitas/pinning sertifikat) untuk seluruh komunikasi data.
- [ ] Mode Client aktif dan pengalihan seluruh repository/transaksi ke database pusat.
- [ ] API transaksi, produk, stok, pelanggan, pembelian, servis, dan laporan dengan pemeriksaan hak akses di Server.
- [ ] WebSocket/notifikasi perubahan data dan mekanisme refresh setelah reconnect.
- [ ] Idempotency key, transaksi atomik, audit request, dan perlindungan transaksi ganda.
- [ ] Kerja serentak lintas perangkat dengan satu database pusat.
- [ ] Pemulihan koneksi, penanganan Server mati, dan pengujian multi-HP secara fisik.

**Catatan:** Menyimpan alamat Server atau menjalankan pemeriksaan jaringan/API tidak berarti Client sudah berbagi database. Sampai layanan Server, autentikasi, dan sinkronisasi selesai diuji, semua transaksi tetap menggunakan database lokal perangkat masing-masing.
## 14. Keamanan dan keandalan

- [x] Database lokal SQLite.
- [x] Migrasi database bertahap sampai skema yang digunakan fitur saat ini; migrasi baru wajib diuji dan tidak boleh menghapus data lama.
- [x] Pengujian otomatis dijalankan pada pipeline CI.
- [x] Pipeline CI memiliki tahap build APK release dan verifikasi tanda tangan.
- [x] Backup database ke file .db dan pemulihan dari file backup dengan validasi integritas, versi, tabel penting, serta salinan pengaman sebelum restore.
- [ ] Uji backup/restore pada berbagai perangkat dan skenario kegagalan.
- [ ] Audit menyeluruh persistensi data setelah aplikasi ditutup/dibuka.
- [ ] Uji perangkat fisik untuk alur utama, printer, kamera, dan berbagi file.
- [x] Login username/PIN, role Admin/Kasir/Mekanik, pembatasan akses dasar, dan activity log untuk tindakan yang telah diintegrasikan.
- [ ] Audit keamanan menyeluruh, kebijakan percobaan login/PIN, dan cakupan pencatatan seluruh aksi pengguna.

## 15. Pengingat dan fitur tambahan

- [x] Daftar piutang gabungan servis dan penjualan barang, termasuk pelanggan umum/guest.
- [x] Filter/pencarian piutang dan rincian sisa tagihan.
- [x] Rincian piutang per nota menampilkan total, pembayaran, sisa, serta riwayat pembayaran; penjualan juga menampilkan retur dan refund.
- [x] Detail pemasok menampilkan riwayat faktur, pembayaran, kredit retur, dan nilai retur; faktur batal tidak dihitung sebagai utang aktif.
- [x] Membuka WhatsApp dengan template pengingat yang dapat ditinjau pengguna.
- [x] Log mencatat waktu WhatsApp dibuka untuk pengingat; aplikasi tidak mengirim pesan otomatis.
- [ ] Pengingat servis berkala dan garansi.
- [x] Pengaturan pengingat stok: aktif/nonaktif, batas Minimum Stok atau stok habis, izin notifikasi Android, dan pengingat berkala.
- [x] Program poin loyalty: aturan perolehan poin dari transaksi penjualan yang memenuhi syarat, saldo/ledger, pembalikan poin saat pembatalan/retur, katalog reward, dan penukaran poin.
- [ ] Voucher/diskon otomatis saat checkout, masa berlaku poin/reward, multi-cabang, dan sinkronisasi cloud.

## Prioritas pengerjaan saat ini

Sesuai arahan, pengembangan sementara dibatasi pada empat area berikut. Fitur di luar empat area ini ditunda sampai audit dan perbaikannya selesai.

1. **Audit riwayat biaya langsung servis** — pastikan biaya awal dan setiap koreksi memiliki jejak nilai lama/baru serta waktu perubahan; migrasi harus mengisi riwayat awal nota lama tanpa mengubah nominal nota.
2. **Audit utang/piutang terperinci** — cocokkan nilai faktur, DP/pembayaran lanjutan, retur/refund, kredit retur pemasok, pembatalan, dan saldo per nota.
3. **Rekonsiliasi Buku Kas dengan transaksi sumber** — pastikan setiap referensi kas dapat dikenali, nominal dan arah kas benar, serta transaksi tanpa sumber atau koreksi terdeteksi.
4. **Audit laporan laba rugi** — validasi periode pengakuan penjualan/servis, retur, HPP, biaya langsung servis, biaya operasional, dan batasan perhitungan laba bersih.

Cetak transaksi langsung Bluetooth/USB/Wi-Fi, integrasi laci uang, papan antrian, dan kompatibilitas perangkat khusus masih perlu dilanjutkan dan diuji. Snapshot historis dokumen sudah tersedia untuk nota yang diterbitkan.

## 16. Saldo deposit pelanggan dan uang tip

- [x] Buku saldo pelanggan tersendiri melalui ledger mutasi; saldo tidak dicampur dengan omzet.
- [x] Admin/Kasir dapat menerima deposit dari halaman pelanggan, memilih metode pembayaran, dan melihat saldo serta riwayat mutasi.
- [x] Saldo deposit pelanggan terdaftar digunakan otomatis untuk mengurangi tagihan POS; sisa pembayaran dibayar dengan metode yang dipilih.
- [x] Saat Admin/Kasir menyelesaikan atau menyerahkan servis, saldo deposit otomatis digunakan untuk mengurangi sisa tagihan servis; akun Mekanik tidak memicu transaksi keuangan.
- [x] Kelebihan pembayaran servis dapat dipilih untuk dikembalikan sebagai kembalian, disimpan sebagai saldo deposit, atau dicatat sebagai tip mekanik.
- [x] Pemakaian saldo dicatat sebagai pembayaran non-kas; tidak membuat pemasukan kas palsu.
- [x] Pembatalan servis/penjualan dan retur penjualan mengembalikan bagian pembayaran yang berasal dari deposit ke saldo pelanggan; bagian pembayaran tunai dikembalikan melalui kas.
- [x] Total titipan deposit pelanggan ditampilkan terpisah pada ringkasan laporan keuangan.
- [x] Uang tip memiliki tabel/ledger terpisah dari nota penjualan/servis dan omzet; tip dapat dicatat pada pembayaran servis atau secara terpisah.
- [x] Laporan tip memiliki filter periode, rekap per penerima/mekanik, status belum diserahkan/sudah diserahkan, dan riwayat tip.
- [x] Penyerahan tip dicatat sebagai pengeluaran kas terpisah dan hanya dapat dikonfirmasi Admin.
- [x] Admin/Kasir dapat menarik saldo pelanggan secara tunai kapan saja selama saldo mencukupi; mutasi saldo dan kas keluar tercatat serta dapat direkonsiliasi.
- [x] Penarikan tunai dicatat sebagai pengurangan titipan pelanggan dan pengeluaran kas, bukan pengurang omzet.
- [ ] Sinkronisasi saldo pelanggan dan tip lintas perangkat; saat ini data tetap lokal pada perangkat.

**Catatan akuntansi:** Deposit merupakan titipan/kewajiban kepada pelanggan, bukan pendapatan bengkel. Tip bukan omzet jasa atau barang. Keduanya tetap muncul pada arus kas karena uang benar-benar diterima, tetapi tidak menambah metrik penjualan/pendapatan dan laba usaha. Penggunaan saldo deposit mengurangi kewajiban saldo pelanggan tanpa menambah kas masuk.

## 17. Biaya modal sparepart servis berbasis FIFO

- [x] Biaya modal sparepart servis dihitung dari batch FIFO yang benar-benar dikonsumsi saat nota dibuat.
- [x] Snapshot biaya FIFO disimpan dalam alokasi sparepart dan riwayat biaya langsung servis.
- [x] Penambahan sparepart yang disetujui menambah biaya modal berdasarkan batch FIFO yang dipakai.
- [x] Pembatalan sparepart yang belum dipakai mengembalikan kuantitas dan mengurangi biaya modal berdasarkan alokasi batch asal.
- [x] Perubahan biaya modal otomatis tercatat dalam riwayat lama/baru agar laporan periode selesai memakai snapshot yang berlaku.
- [ ] Pengujian fisik alur FIFO servis, retur/pembatalan, dan laporan laba/rugi pada perangkat pengguna.

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


## Fitur pemeliharaan transaksi percobaan (belum diimplementasikan)

Tujuan fitur ini adalah membersihkan transaksi yang dibuat saat pertama kali mencoba/mempelajari aplikasi, bukan menghapus transaksi operasional yang benar-benar terjadi.

Ketentuan yang disepakati:
- Menu khusus Admin di Pengaturan untuk pemeliharaan data transaksi.
- Mendukung transaksi lama yang dibuat sebelum fitur tersedia; Admin harus memilih transaksi lama secara manual karena belum memiliki penanda percobaan.
- Mendukung penjualan, pembelian, dan servis; transaksi terkait pembayaran/piutang/hutang juga harus diperiksa.
- Pilihan satu transaksi atau beberapa transaksi, dengan filter jenis dan tanggal serta ringkasan dampak sebelum konfirmasi.
- Transaksi operasional tidak boleh terhapus otomatis. Jangan menganggap transaksi sebagai percobaan hanya berdasarkan tanggal, nominal, pelanggan umum, atau status lunas.
- Penghapusan hanya boleh dilakukan bila seluruh dampak terkait dapat dibalik secara atomik: stok dan batch biaya, kas, saldo deposit, poin loyalty, retur, pembayaran, piutang/hutang, tip, foto/dokumen, dan referensi laporan.
- Jika dependensi keuangan/stok tidak dapat dibalik secara aman, transaksi harus ditolak dari penghapusan dan alasan penolakan ditampilkan. Gunakan proses pembatalan/koreksi yang ada bila sesuai; jangan meninggalkan referensi yatim.
- Sediakan penanda Mode Percobaan untuk transaksi baru pada tahap implementasi berikutnya agar mudah dikenali, tanpa mengubah alur transaksi operasional.
- Backup sebelum pembersihan massal dan catat aktivitas Admin.

Status: spesifikasi disepakati; UI, repository, migrasi/penanda percobaan, penghapusan aman, dan tes otomatis belum dibuat. Fitur hapus nota servis yang sudah ada bukan pengganti fitur pembersihan lintas-modul ini.

## 18. Backup lengkap lokal dan Google Drive

Keputusan pengguna: backup Bike POS menggunakan **penyimpanan lokal dan Google Drive**.

Spesifikasi yang disepakati:
- [ ] Paket backup lengkap berisi database SQLite dan seluruh media yang direferensikan database.
- [ ] Media yang harus dicakup: foto produk, foto profil pelanggan (saat ini tersimpan sebagai Base64 di database), foto sebelum/sesudah servis, logo usaha, foto profil akun, serta media lain yang ditambahkan oleh modul aplikasi.
- [ ] Simpan backup lokal di penyimpanan perangkat atau lokasi yang dipilih pengguna; proses pembuatan backup harus tetap dapat berjalan tanpa internet.
- [ ] Sediakan ekspor/simpan ke Google Drive ketika layanan Drive tersedia dan pengguna telah memberi izin. Kegagalan internet/Drive tidak boleh membatalkan backup lokal.
- [ ] Sediakan daftar backup dengan tanggal, ukuran, versi aplikasi/skema, dan ringkasan jumlah file media; jangan menimpa backup lama secara diam-diam.
- [ ] Pemulihan memvalidasi arsip, integritas SQLite, versi skema, dan kelengkapan media sebelum mengganti data aktif.
- [ ] Pemulihan ke perangkat baru harus memetakan ulang lokasi file media agar foto tetap terbaca, serta membuat salinan pengaman data aktif sebelum pemulihan.
- [ ] Batasi buat/pulihkan backup untuk Admin dan catat aktivitasnya.
- [ ] Uji backup database + media, arsip rusak, media hilang, pemulihan gagal, dan pemulihan ke direktori/perangkat berbeda.

Kondisi kode saat keputusan ini dicatat:
- Menu Backup & Pemulihan dan layanan backup database `.db` sudah ada.
- Backup yang ada belum mengemas file media dan belum menyediakan integrasi Google Drive langsung.
- Alur berbagi file Android dapat digunakan sebagai tahap ekspor manual ke aplikasi penyimpanan yang kompatibel; ini **bukan** sinkronisasi atau unggah otomatis Google Drive.
- Implementasi paket backup lengkap, pemetaan ulang media, dan alur Google Drive masih belum selesai.

Urutan pengerjaan: (1) inventaris seluruh kolom/lokasi media, (2) paket arsip database + media dan validasi, (3) pemulihan aman beserta pemetaan ulang path, (4) penyimpanan lokal dan riwayat backup, (5) integrasi Google Drive dengan izin pengguna, lalu (6) pengujian pemulihan lintas perangkat. Backup lokal harus tetap berfungsi mandiri bila Drive tidak tersedia.


## 19. Data contoh pembelian untuk Admin

Keputusan pengguna: sediakan data contoh yang dapat dibuat dan dicoba langsung dari aplikasi, khusus untuk Admin.

Ketentuan:
- Menu/aksi **Buat Data Contoh Pembelian** hanya dapat diakses Admin.
- Data contoh tidak dibuat otomatis saat aplikasi dipasang atau dibuka; Admin harus memilih membuatnya.
- Setiap data contoh wajib memiliki penanda khusus (mis. `is_test_data` atau sumber `test_seed`) yang tersimpan di database, bukan hanya teks pada catatan.
- Semua nomor faktur, pemasok, pesanan marketplace, pembayaran, mutasi stok, batch HPP, dan transaksi kas yang dibuat oleh seeder harus dapat ditelusuri ke satu kelompok data contoh.
- Sediakan skenario: pembelian langsung lunas, pembelian online dengan diskon dan rincian ongkir/packing/asuransi/admin/biaya lain, pembelian online dibayar sebagian, serta penerimaan barang sebagian dan lengkap setelah alur penerimaan tersedia.
- Gunakan pemasok/produk contoh khusus atau data master yang memang dibuat oleh seeder; jangan mengubah harga, stok, atau data master operasional yang sudah ada.
- Data contoh harus terlihat jelas dengan label **DATA TEST** pada daftar dan detail, serta tidak boleh dianggap transaksi operasional.
- Sediakan aksi **Hapus Semua Data Contoh** khusus Admin dengan pratinjau jumlah dan dampak. Hapus hanya record yang ditandai sebagai data contoh dan semua relasi turunannya secara atomik; bila ada dependensi yang tidak aman dibalik, batalkan penghapusan dan tampilkan alasannya.
- Data contoh tidak boleh masuk ke omzet, laba/rugi, utang pemasok operasional, saldo kas fisik, atau laporan transaksi nyata. Filter laporan harus mengecualikan data contoh secara konsisten.
- Tambahkan tes otomatis untuk hak akses Admin, penanda data contoh, tidak adanya perubahan data operasional, isolasi laporan, dan pembersihan relasi tanpa data yatim.

Urutan implementasi: selesaikan terlebih dahulu alur pembelian dan penerimaan barang agar stok hanya bertambah saat barang benar-benar diterima; setelah itu buat seeder dan pembersihan aman, lalu uji seluruh skenario.
