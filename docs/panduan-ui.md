# Panduan UI BengkelKu POS

Panduan ini menjadi standar visual untuk seluruh layar aplikasi. Perubahan dilakukan bertahap per modul agar alur transaksi dan fungsi yang sudah stabil tidak rusak.

## Prinsip
- Tema terang; hindari halaman gelap atau teks putih di atas latar putih.
- Tampilan ringkas, profesional, dan mudah dibaca di HP kasir maupun tablet.
- Pertahankan header dan navigasi bawah; area konten tengah yang boleh bergulir.
- Gunakan komponen dan tema global dari `lib/core/theme/app_theme.dart`.
- Jangan mengubah perilaku bisnis, hak akses, atau urutan transaksi hanya demi perubahan visual.

## Warna
- Primary: biru `#1558A6`.
- Aksen: hijau `#16866A` untuk status/aksi yang sesuai.
- Latar halaman: `#F4F6F9`.
- Permukaan kartu/form: putih.
- Garis/border: `#DCE2E9`.
- Teks utama: `#202A36`; teks sekunder: `#687586`.
- Merah hanya untuk tindakan berbahaya atau kesalahan; kuning untuk peringatan.

## Kontrol
- Tombol utama memakai biru, tombol sekunder memakai outline, dan tindakan berbahaya memakai merah.
- Gunakan tinggi minimum sekitar 40 dp dan radius 10 dp; hindari tombol terlalu besar atau label terpotong.
- Form input memakai label yang jelas, hint seperlunya, padding konsisten, dan pesan validasi yang dekat dengan field.
- Dropdown harus mudah disentuh, memiliki label, dan tidak memotong pilihan panjang.
- Gunakan ukuran teks sekitar 13–14 sp untuk isi, 15–18 sp untuk judul bagian, dan 11 sp untuk keterangan sekunder.
- Jaga kontras teks, status, ikon, dan tombol.

## Foto
- Foto produk dan dokumentasi servis menggunakan `AppPhotoPreview` agar ukuran, radius, placeholder, latar, dan error state konsisten.
- Foto memakai `BoxFit.cover` untuk thumbnail dan tidak boleh meluber keluar frame.
- Foto nota/struk merupakan pengecualian: tampilan preview, hasil foto WhatsApp, format cetak, dan alur nota harus tetap persis seperti keputusan yang sudah disetujui; jangan menerapkan perubahan visual umum pada modul nota tanpa permintaan khusus.

## Checklist review setiap modul
- [ ] Konsisten dengan tema terang dan palet aplikasi.
- [ ] Tombol utama/sekunder/berbahaya jelas dan tidak terpotong.
- [ ] Input, dropdown, dialog, dan popup seragam.
- [ ] Font, jarak, dan kepadatan sesuai layar HP/tablet.
- [ ] Kartu, tabel, status kosong, loading, dan error state rapi.
- [ ] Foto memiliki rasio, crop, placeholder, dan error state yang benar.
- [ ] Tidak ada perubahan pada alur transaksi atau format nota.
- [ ] Build, analyzer, dan tes terkait lulus.
