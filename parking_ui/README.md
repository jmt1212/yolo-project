# Deteksi Lot Parkir — UI Flutter

Aplikasi untuk mengelola foto parkiran per gedung, mengatur slot parkir secara manual,
dan menjalankan deteksi YOLO lewat backend di `../backend`.

## Fitur

- **Daftar gedung**: Gedung T, Q, dan W sudah tersedia. Gedung bisa ditambah, diganti nama, dan dihapus.
- **Foto per gedung**: unggah satu atau beberapa foto parkiran sekaligus.
- **Atur slot manual**: mode *Gambar slot* (tarik di foto untuk membuat slot) dan *Pilih / ubah*
  (klik untuk memilih, geser untuk memindah, tarik sudut untuk mengubah ukuran, ganti nama, hapus).
- **Deteksi**: pilih model untuk tiap deteksi. Hasilnya berupa status per slot (kosong / terisi / anomali)
  dan kotak mobil yang ditemukan YOLO.
- **Pengaturan model**: jelajahi folder di komputer server, pilih folder model dan model aktif (`.pt`),
  lalu atur ambang *confidence* dan *overlap*.

## Menjalankan

Butuh dua terminal, dijalankan dari folder repo `Manpro-Parking-Detection`.

**1. Backend (port 8001)**

```powershell
cd backend
..\trial1\.venv\Scripts\python.exe main.py
```

Data (gedung, foto, slot) disimpan di `backend/data/`. Hapus folder itu untuk kembali ke data awal.

**2. UI Flutter**

Flutter SDK ada di `C:\Users\jia\flutter`. Tambahkan `C:\Users\jia\flutter\bin` ke PATH,
atau panggil dengan path lengkap:

```powershell
cd parking_ui
C:\Users\jia\flutter\bin\flutter.bat run -d edge
```

Untuk versi rilis tanpa mode debug:

```powershell
C:\Users\jia\flutter\bin\flutter.bat build web
..\trial1\.venv\Scripts\python.exe -m http.server 5600 --directory build\web
```

Lalu buka http://localhost:5600.

Alamat backend default-nya `http://127.0.0.1:8001`. Kalau berbeda, ubah di
**Pengaturan Model → Alamat server**.

## Struktur kode

| File | Isi |
|---|---|
| `lib/api.dart` | Klien HTTP ke backend dan model data (Gedung, Foto, Slot, hasil deteksi) |
| `lib/common.dart` | Warna status, dialog, dan widget kecil yang dipakai bersama |
| `lib/pages/building_list_page.dart` | Daftar gedung |
| `lib/pages/building_page.dart` | Foto dalam satu gedung dan unggah foto |
| `lib/pages/photo_page.dart` | Editor slot dan panel deteksi |
| `lib/pages/model_page.dart` | Pilih folder model, model aktif, ambang deteksi, alamat server |
| `lib/widgets/slot_canvas.dart` | Gambar foto dan slot, serta gestur gambar / pindah / ubah ukuran |

Koordinat slot selalu disimpan dalam piksel foto asli, sama seperti yang dipakai YOLO.
`SlotCanvas` yang mengubahnya ke ukuran layar.
