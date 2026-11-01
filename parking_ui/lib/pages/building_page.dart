import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import 'photo_page.dart';
import '../widgets/petra.dart';

/// Daftar foto parkiran dalam satu gedung, plus unggah foto baru.
class BuildingPage extends StatefulWidget {
  const BuildingPage({super.key, required this.building});
  final Building building;

  @override
  State<BuildingPage> createState() => _BuildingPageState();
}

class _BuildingPageState extends State<BuildingPage> {
  List<Photo>? _photos;
  late Building _building = widget.building;
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([api.photos(widget.building.id), api.building(widget.building.id)]);
      if (mounted) {
        setState(() {
          _photos = results[0] as List<Photo>;
          _building = results[1] as Building;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(type: FileType.image, dialogTitle: 'Pilih foto parkiran');
    if (picked.isEmpty) return;
    setState(() => _uploading = true);
    var done = 0;
    final failed = <String>[];
    for (final file in picked) {
      try {
        await api.uploadPhoto(widget.building.id, file.name, await file.readAsBytes());
        done++;
      } on ApiException catch (e) {
        failed.add('${file.name} (${e.message})');
      } catch (_) {
        failed.add('${file.name} (tidak bisa dibaca)');
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    showMessage(
      context,
      failed.isEmpty ? '$done foto diunggah' : '$done foto diunggah, gagal: ${failed.join(', ')}',
      error: failed.isNotEmpty,
    );
    await _load();
  }

  Future<void> _delete(Photo p) async {
    if (!await confirm(context, 'Hapus foto?', '${p.originalName} beserta konfigurasi slotnya akan dihapus.')) return;
    try {
      await api.deletePhoto(p.id);
      if (mounted) showMessage(context, 'Foto dihapus');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  Future<void> _open(Photo p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoPage(photoId: p.id, title: p.originalName, labelPrefix: _building.code),
      ),
    );
    await _load();
  }

  Future<void> _setLayout(Photo p) async {
    try {
      await api.updateBuilding(_building.id, layoutPhotoId: p.id);
      if (mounted) showMessage(context, '${p.originalName} menjadi foto acuan ${_building.name}');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      appBar: AppBar(
        title: Text(_building.name),
        actions: [IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: _uploading
            ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading || _error != null ? null : _upload,
        icon: const Icon(Icons.upload),
        label: Text(_uploading ? 'Mengunggah...' : 'Unggah foto'),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : photos == null
          ? const Center(child: CircularProgressIndicator())
          : photos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Belum ada foto parkiran untuk ${widget.building.name}.'),
                  const SizedBox(height: 4),
                  const Text('Unggah foto, lalu atur slot parkirnya.'),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LayoutNote(building: _building),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (context, i) => _PhotoCard(
                      photo: photos[i],
                      isLayout: photos[i].id == _building.layoutPhotoId,
                      onTap: () => _open(photos[i]),
                      onDelete: () => _delete(photos[i]),
                      onSetLayout: () => _setLayout(photos[i]),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.isLayout,
    required this.onTap,
    required this.onDelete,
    required this.onSetLayout,
  });
  final Photo photo;
  final bool isLayout;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSetLayout;

  @override
  Widget build(BuildContext context) {
    final result = photo.lastResult;
    final muted = Theme.of(context).textTheme.bodySmall;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    api.photoImageUrl(photo.id),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                  if (isLayout) const Positioned(left: 8, top: 8, child: TagLabel('FOTO ACUAN')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(photo.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          '${photo.width} × ${photo.height} px · '
                          '${photo.slots.isEmpty ? 'belum ada slot' : '${photo.slots.length} slot'}',
                          style: muted,
                        ),
                        const SizedBox(height: 6),
                        result == null ? Text('Belum dideteksi', style: muted) : SummaryChips(summary: result.summary),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opsi',
                    onSelected: (v) => v == 'layout' ? onSetLayout() : onDelete(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'layout',
                        enabled: !isLayout && photo.slots.isNotEmpty,
                        child: Text(photo.slots.isEmpty ? 'Jadikan foto acuan (atur slot dulu)' : 'Jadikan foto acuan'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('Hapus foto')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Penjelasan foto acuan di atas daftar foto.
class _LayoutNote extends StatelessWidget {
  const _LayoutNote({required this.building});
  final Building building;

  @override
  Widget build(BuildContext context) {
    final text = building.layoutPhotoId == null
        ? 'Belum ada foto acuan. Buka satu foto, atur slot parkirnya, lalu jadikan foto acuan. '
              'Posisi lot di foto acuan dipakai untuk semua foto yang diunggah pengunjung.'
        : 'Foto acuan berisi ${building.lotCount} lot. Posisi lot ini dipakai untuk semua foto yang diunggah '
              'pengunjung, jadi foto pengunjung sebaiknya diambil dari sudut kamera yang sama.';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
