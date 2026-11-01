# PetraPark — Deteksi Lot Parkir

Aplikasi untuk mengecek ketersediaan lot parkir dari foto. Pengunjung memilih gedung dan mengunggah
foto parkiran. Model YOLO lalu mendeteksi mobil, dan setiap lot ditandai **kosong** (hijau),
**terisi** (merah), atau **anomali** (kuning, terdeteksi lebih dari satu kendaraan).

Proyek ini terdiri dari dua bagian yang dijalankan bersamaan:

| Folder | Isi | Alamat saat berjalan |
|---|---|---|
| `backend/` | API Python (FastAPI + YOLO) yang menyimpan gedung, foto, dan lot, lalu menjalankan deteksi | http://127.0.0.1:8001 |
| `parking_ui/` | Tampilan aplikasi (Flutter) | http://localhost:5600 (atau jendela Edge/Chrome) |
| `trial1/` | Model YOLO (`best*.pt`), foto contoh, dan prototipe awal | — |

---

## 1. Yang perlu dipasang (sekali saja)

| Perangkat | Versi | Keterangan |
|---|---|---|
| **Python** | 3.10 atau lebih baru (disarankan 3.12) | https://www.python.org/downloads/. Saat memasang di Windows, centang **"Add python.exe to PATH"**. |
| **Flutter SDK** | 3.x stable | https://docs.flutter.dev/get-started/install. Hanya perlu untuk menjalankan atau membangun tampilan. |
| **Git** | versi apa saja | https://git-scm.com/downloads |
| **Browser** | Microsoft Edge atau Google Chrome | Untuk membuka aplikasi |

Cek pemasangan di terminal (PowerShell):

```powershell
python --version
flutter --version
git --version
```

---

## 2. Ambil kode proyek

```powershell
git clone git@github.com:jmt1212/yolo-project.git
cd yolo-project
```

> Jika belum punya SSH key di GitHub, pakai alamat HTTPS:
> `git clone https://github.com/jmt1212/yolo-project.git`

---

## 3. Siapkan backend (sekali saja)

Buat *virtual environment* Python di folder proyek, lalu pasang paket yang dibutuhkan:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
```

Pemasangan ini mengunduh PyTorch dan Ultralytics (sekitar 1 GB), jadi bisa memakan waktu beberapa menit.

> **macOS / Linux:** ganti `.\.venv\Scripts\python.exe` dengan `.venv/bin/python`.

---

## 4. Jalankan aplikasi

Buka **dua terminal**, keduanya di folder proyek.

### Terminal 1 — backend

```powershell
cd backend
..\.venv\Scripts\python.exe main.py
```

Tunggu sampai muncul tulisan `Uvicorn running on http://127.0.0.1:8001`. Biarkan terminal ini tetap terbuka.

Pada percobaan pertama, backend otomatis membuat data awal di `backend/data/`: **Gedung T, Q, dan W**.
Gedung Q sudah berisi foto contoh beserta 9 lot.

Cek backend dengan membuka http://127.0.0.1:8001/api/health di browser. Hasilnya harus `{"status":"ok"}`.

### Terminal 2 — tampilan (pilih salah satu cara)

**Cara A — mode pengembangan (paling mudah):**

```powershell
cd parking_ui
flutter pub get
flutter run -d edge
```

Ganti `edge` dengan `chrome` jika memakai Google Chrome. Jendela browser terbuka otomatis setelah proses
kompilasi selesai (sekitar 1 menit).

**Cara B — versi rilis (lebih cepat saat dipakai):**

```powershell
cd parking_ui
flutter build web
..\.venv\Scripts\python.exe -m http.server 5600 --bind 127.0.0.1 --directory build\web
```

Lalu buka **http://localhost:5600** di browser.

### Menghentikan aplikasi

Klik terminal yang bersangkutan lalu tekan **Ctrl + C**. Lakukan di kedua terminal.

---

## 5. Cara memakai

### Pengunjung

1. **Pilih gedung** di halaman utama.
2. **Unggah foto** parkiran: tarik dan lepas foto ke kotak unggah, atau tekan *Pilih foto* (JPG, PNG, WEBP).
3. Periksa **posisi lot** pada foto. Lot terisi otomatis dari tata letak gedung, dan bisa diubah:
   - **Pilih / ubah**: klik lot, geser untuk memindah, tarik sudut untuk mengubah ukuran, ganti nama, atau hapus.
   - **Gambar lot**: tarik kotak di foto untuk menambah lot baru.
4. Tekan **Deteksi parkir**. Hasilnya berupa foto dengan lot berwarna, ringkasan jumlah lot, dan daftar lot kosong.
5. Tekan **Ubah posisi lot** untuk memperbaiki lot lalu mendeteksi ulang, atau **Unggah foto baru**.

### Admin (tombol **Kelola** di kanan atas)

- **Kelola gedung**: tambah, ubah nama/lokasi, atau hapus gedung.
- **Foto acuan**: buka gedung, unggah foto, atur lotnya, lalu pilih *Jadikan foto acuan* lewat menu ⋮ pada foto.
  Lot di foto acuan dipakai sebagai posisi awal untuk semua foto yang diunggah pengunjung di gedung itu.
  Hasil terbaik didapat jika foto pengunjung diambil dari sudut kamera yang sama.
- **Model deteksi**: pilih folder dan file model YOLO (`.pt`), atur ambang *confidence* dan *overlap*,
  dan ubah alamat server jika backend tidak berjalan di `http://127.0.0.1:8001`.
  Model bawaan ada di `trial1/`; yang aktif secara default adalah `best_3.pt`.

---

## 6. Masalah yang sering terjadi

| Gejala | Penyebab dan solusi |
|---|---|
| Header menampilkan **"Sistem tidak terhubung"** atau muncul *"Tidak dapat terhubung ke server"* | Backend belum berjalan. Jalankan Terminal 1 (langkah 4). Pastikan alamat di *Kelola → Model deteksi → Alamat server* adalah `http://127.0.0.1:8001`. |
| `ModuleNotFoundError: No module named 'fastapi'` (atau `ultralytics`) | Backend dijalankan dengan Python yang salah. Pakai `..\.venv\Scripts\python.exe main.py`, bukan `python main.py`, dan pastikan langkah 3 sudah dilakukan. |
| `No Python at '...'` saat menjalankan `.venv` | Python yang dipakai saat membuat `.venv` sudah dipindah atau dihapus. Hapus folder `.venv` lalu ulangi langkah 3. |
| `address already in use` / port 8001 atau 5600 terpakai | Aplikasi sudah berjalan di terminal lain. Tutup dulu (Ctrl + C), atau cari prosesnya dengan `Get-NetTCPConnection -LocalPort 8001` lalu hentikan dengan `Stop-Process -Id <nomor>`. |
| `flutter` tidak dikenali | Folder `bin` Flutter belum ada di PATH. Tambahkan, atau panggil dengan path lengkap, mis. `C:\Users\<nama>\flutter\bin\flutter.bat`. |
| Flutter meminta **Developer Mode** | Hanya diperlukan untuk membangun aplikasi Windows desktop. Untuk versi web (Edge/Chrome) peringatan ini bisa diabaikan. |
| Lot berstatus **anomali** padahal hanya ada satu mobil | Model kadang memberi lebih dari satu kotak pada satu mobil. Coba ubah ambang di *Kelola → Model deteksi*, atau perkecil kotak lot. |
| Hasil semuanya **kosong** padahal ada mobil | Model yang aktif mungkin tidak punya kelas `car` (mis. `best_2.pt`). Pilih `best_3.pt` di *Kelola → Model deteksi*. |

---

## Struktur folder

```
yolo-project/
├── backend/            API FastAPI (main.py) dan requirements.txt
│   └── data/           Data gedung, foto, dan lot (dibuat otomatis, tidak masuk git)
├── parking_ui/         Aplikasi Flutter (lihat parking_ui/README.md untuk detail kode)
├── trial1/             Model YOLO .pt, foto contoh, dan prototipe awal (app.py + index.html)
└── README.md           Dokumen ini
```

Untuk mengulang dari data awal, hentikan backend lalu hapus folder `backend/data/`.
Data awal dibuat lagi saat backend dijalankan berikutnya.
