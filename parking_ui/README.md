# PetraPark — UI Flutter deteksi lot parkir

Tampilan mengikuti wireframe Figma "Wireframe Deteksi Lot Parkiran". Deteksi dijalankan oleh
backend YOLO di `../backend`.

## Alur pengunjung (3 langkah)

1. **Pilih gedung**: kartu gedung beserta lokasinya, mis. Gedung T · Kampus Timur.
2. **Unggah foto**: tarik dan lepas foto atau pilih dari perangkat (JPG, PNG, WEBP), periksa fotonya,
   lalu tekan *Deteksi parkir*.
3. **Hasil deteksi**: foto dengan posisi lot, kotak kode lot (mis. Q-01) berstatus kosong / terisi / anomali,
   dan ringkasan jumlah lot.

Ada juga tampilan untuk proses yang sedang berjalan (bisa *Batalkan*), hasil kosong (0 lot dikenali),
dan deteksi gagal (*Coba lagi* tanpa mengunggah ulang).

## Kelola (admin)

Tombol **Kelola** di header membuka:

- **Kelola gedung**: tambah, ubah nama/lokasi, dan hapus gedung.
- **Foto per gedung dan foto acuan**: unggah foto, atur slot secara manual (mode *Gambar slot* dan
  *Pilih / ubah*), lalu tandai satu foto sebagai **foto acuan**. Posisi lot di foto acuan dipakai untuk
  semua foto yang diunggah pengunjung di gedung itu, dan diskalakan ke ukuran foto. Karena itu foto
  pengunjung sebaiknya diambil dari sudut kamera yang sama.
- **Model deteksi**: jelajahi folder di komputer server, pilih folder dan model aktif (`.pt`),
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
**Kelola → Model deteksi → Alamat server**.

## Struktur kode

| File | Isi |
|---|---|
| `lib/api.dart` | Klien HTTP ke backend dan model data (Gedung, Foto, Slot, hasil deteksi) |
| `lib/common.dart` | Warna status, dialog, dan widget kecil yang dipakai bersama |
| `lib/theme.dart`, `lib/widgets/petra.dart` | Tema monokrom PetraPark, header/footer, stepper, panel |
| `lib/pages/home_page.dart` | Langkah 1: pilih gedung |
| `lib/pages/detect_flow_page.dart` | Langkah 2–3: unggah foto, proses, hasil, hasil kosong, gagal |
| `lib/pages/building_list_page.dart` | Kelola: daftar gedung |
| `lib/pages/building_page.dart` | Kelola: foto dalam satu gedung dan foto acuan |
| `lib/pages/photo_page.dart` | Editor slot dan panel deteksi |
| `lib/pages/model_page.dart` | Pilih folder model, model aktif, ambang deteksi, alamat server |
| `lib/widgets/slot_canvas.dart` | Gambar foto dan slot, serta gestur gambar / pindah / ubah ukuran |

Koordinat slot selalu disimpan dalam piksel foto asli, sama seperti yang dipakai YOLO.
`SlotCanvas` yang mengubahnya ke ukuran layar.
