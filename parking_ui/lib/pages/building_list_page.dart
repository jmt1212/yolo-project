import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import 'building_page.dart';
import 'model_page.dart';
import '../widgets/petra.dart';

/// Halaman utama: daftar gedung.
class BuildingListPage extends StatefulWidget {
  const BuildingListPage({super.key});

  @override
  State<BuildingListPage> createState() => _BuildingListPageState();
}

class _BuildingListPageState extends State<BuildingListPage> {
  List<Building>? _buildings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final buildings = await api.buildings();
      if (mounted) setState(() => _buildings = buildings);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) showMessage(context, success);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  /// Dialog nama + lokasi gedung. Mengembalikan null jika dibatalkan.
  Future<(String, String)?> _askBuilding(String title, {String name = '', String location = ''}) {
    final nameCtl = TextEditingController(text: name);
    final locCtl = TextEditingController(text: location);
    return showDialog<(String, String)>(
      context: context,
      builder: (context) {
        void submit() => Navigator.pop(context, (nameCtl.text.trim(), locCtl.text.trim()));
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama gedung', hintText: 'Gedung P'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtl,
                decoration: const InputDecoration(labelText: 'Lokasi', hintText: 'Kampus Pusat'),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(onPressed: submit, child: const Text('Simpan')),
          ],
        );
      },
    );
  }

  Future<void> _add() async {
    final input = await _askBuilding('Tambah gedung');
    if (input == null || input.$1.isEmpty) return;
    await _run(() => api.addBuilding(input.$1, input.$2), '${input.$1} ditambahkan');
  }

  Future<void> _edit(Building b) async {
    final input = await _askBuilding('Ubah gedung', name: b.name, location: b.location);
    if (input == null || input.$1.isEmpty) return;
    await _run(() => api.updateBuilding(b.id, name: input.$1, location: input.$2), 'Perubahan disimpan');
  }

  void _openModels() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelPage())).then((_) => _load());

  Future<void> _delete(Building b) async {
    final ok = await confirm(
      context,
      'Hapus ${b.name}?',
      'Semua foto (${b.photoCount}) dan konfigurasi slotnya ikut terhapus. Tindakan ini tidak bisa dibatalkan.',
    );
    if (ok) await _run(() => api.deleteBuilding(b.id), '${b.name} dihapus');
  }

  @override
  Widget build(BuildContext context) {
    final buildings = _buildings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola gedung'),
        actions: [
          if (MediaQuery.sizeOf(context).width < 600)
            IconButton(tooltip: 'Model deteksi', icon: const Icon(Icons.memory), onPressed: _openModels)
          else
            TextButton.icon(
              icon: const Icon(Icons.memory, size: 18),
              label: const Text('Model deteksi'),
              onPressed: _openModels,
            ),
          IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _error == null ? _add : null,
        icon: const Icon(Icons.add),
        label: const Text('Tambah gedung'),
      ),
      body: _error != null
          ? ErrorView(message: '$_error\n\nPastikan backend sudah berjalan.', onRetry: _load)
          : buildings == null
          ? const Center(child: CircularProgressIndicator())
          : buildings.isEmpty
          ? const Center(child: Text('Belum ada gedung. Tekan "Tambah gedung" untuk mulai.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: buildings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final b = buildings[i];
                return Card(
                  child: ListTile(
                    leading: BuildingTile(code: b.code, size: 40),
                    title: Text(b.name),
                    subtitle: Text(
                      [
                        if (b.location.isNotEmpty) b.location,
                        '${b.photoCount} foto',
                        b.lotCount == 0 ? 'lot belum diatur' : '${b.lotCount} lot',
                      ].join(' · '),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BuildingPage(building: b)),
                    ).then((_) => _load()),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Opsi',
                      onSelected: (v) => v == 'edit' ? _edit(b) : _delete(b),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Ubah nama / lokasi')),
                        PopupMenuItem(value: 'delete', child: Text('Hapus')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
