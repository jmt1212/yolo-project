import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';

/// Satu klien API untuk seluruh aplikasi. Alamat bisa diubah di halaman Pengaturan Model.
final api = ApiClient('http://127.0.0.1:8001');

/// Status koneksi ke backend untuk indikator "Sistem aktif" di header (null = belum dicek).
final serverOnline = ValueNotifier<bool?>(null);

Timer? _healthTimer;

void startHealthChecks() {
  Future<void> check() async {
    try {
      await api.health();
      serverOnline.value = true;
    } on ApiException {
      serverOnline.value = false;
    }
  }

  check();
  _healthTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => check());
}

/// Hijau = kosong, merah = terisi, kuning = anomali (lebih dari satu kendaraan di satu lot).
const statusColors = {'empty': Color(0xFF2E9E5B), 'occupied': Color(0xFFD64545), 'anomaly': Color(0xFFF2B705)};

/// Warna teks di atas warna status (kuning butuh teks gelap agar terbaca).
Color statusTextColor(String? status) => status == 'anomaly' ? const Color(0xFF3D2E00) : Colors.white;

/// Nama lot berikutnya, mis. "T-07" jika nomor terbesar yang ada adalah 6.
String nextSlotLabel(List<Slot> slots, String prefix) {
  var max = 0;
  for (final s in slots) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(s.label);
    if (m != null && int.parse(m.group(1)!) > max) max = int.parse(m.group(1)!);
  }
  return '$prefix-${(max + 1).toString().padLeft(2, '0')}';
}

const statusLabels = {'empty': 'Kosong', 'occupied': 'Terisi', 'anomaly': 'Anomali'};

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Hapus'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Simpan')),
      ],
    ),
  );
}

/// Tampilan saat data gagal dimuat, dengan tombol coba lagi.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

/// Ringkasan hasil deteksi: kosong / terisi / anomali.
class SummaryChips extends StatelessWidget {
  const SummaryChips({super.key, required this.summary});
  final Summary summary;

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, int value) => Chip(
      avatar: CircleAvatar(backgroundColor: statusColors[key], radius: 6),
      label: Text('$value ${statusLabels[key]!.toLowerCase()}'),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [chip('empty', summary.empty), chip('occupied', summary.occupied), chip('anomaly', summary.anomaly)],
    );
  }
}
