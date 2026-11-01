import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import 'photo_page.dart';

/// Daftar foto parkiran dalam satu gedung, plus unggah foto baru.
class BuildingPage extends StatefulWidget {
  const BuildingPage({super.key, required this.building});
  final Building building;

  @override
  State<BuildingPage> createState() => _BuildingPageState();
}

class _BuildingPageState extends State<BuildingPage> {
  List<Photo>? _photos;
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
      final photos = await api.photos(widget.building.id);
      if (mounted) setState(() => _photos = photos);
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoPage(photoId: p.id, title: p.originalName)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.building.name),
        actions: [IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: _uploading ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
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
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.photo_library_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('Belum ada foto parkiran untuk ${widget.building.name}.'),
                        const SizedBox(height: 4),
                        const Text('Unggah foto, lalu atur slot parkirnya.'),
                      ]),
                    )
                  : GridView.builder(
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
                        onTap: () => _open(photos[i]),
                        onDelete: () => _delete(photos[i]),
                      ),
                    ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.photo, required this.onTap, required this.onDelete});
  final Photo photo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final result = photo.lastResult;
    final muted = Theme.of(context).textTheme.bodySmall;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Image.network(
              api.photoImageUrl(photo.id),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(photo.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${photo.width} × ${photo.height} px · '
                      '${photo.slots.isEmpty ? 'belum ada slot' : '${photo.slots.length} slot'}',
                      style: muted),
                  const SizedBox(height: 6),
                  result == null
                      ? Text('Belum dideteksi', style: muted)
                      : SummaryChips(summary: result.summary),
                ]),
              ),
              IconButton(tooltip: 'Hapus foto', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
            ]),
          ),
        ]),
      ),
    );
  }
}
