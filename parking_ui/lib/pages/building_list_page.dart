import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import 'building_page.dart';
import 'model_page.dart';

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

  Future<void> _add() async {
    final name = await askText(context, 'Tambah gedung', hint: 'Contoh: Gedung P');
    if (name == null || name.trim().isEmpty) return;
    await _run(() => api.addBuilding(name.trim()), '${name.trim()} ditambahkan');
  }

  Future<void> _rename(Building b) async {
    final name = await askText(context, 'Ganti nama gedung', initial: b.name);
    if (name == null || name.trim().isEmpty || name.trim() == b.name) return;
    await _run(() => api.renameBuilding(b.id, name.trim()), 'Nama diganti menjadi ${name.trim()}');
  }

  Future<void> _delete(Building b) async {
    final ok = await confirm(context, 'Hapus ${b.name}?',
        'Semua foto (${b.photoCount}) dan konfigurasi slotnya ikut terhapus. Tindakan ini tidak bisa dibatalkan.');
    if (ok) await _run(() => api.deleteBuilding(b.id), '${b.name} dihapus');
  }

  String _initial(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    final word = words.length > 1 && words.first.toLowerCase() == 'gedung' ? words[1] : words.first;
    return word.isEmpty ? '?' : word[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final buildings = _buildings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deteksi Lot Parkir'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan model',
            icon: const Icon(Icons.memory),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelPage()))
                .then((_) => _load()),
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
                            leading: CircleAvatar(child: Text(_initial(b.name))),
                            title: Text(b.name),
                            subtitle: Text(b.photoCount == 0 ? 'Belum ada foto' : '${b.photoCount} foto parkiran'),
                            onTap: () => Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => BuildingPage(building: b)))
                                .then((_) => _load()),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Opsi',
                              onSelected: (v) => v == 'rename' ? _rename(b) : _delete(b),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
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
