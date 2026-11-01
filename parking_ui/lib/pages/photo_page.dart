import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../widgets/slot_canvas.dart';

/// Atur slot parkir pada satu foto secara manual, lalu jalankan deteksi.
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, required this.photoId, required this.title});
  final String photoId;
  final String title;

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  Photo? _photo;
  String? _error;
  List<Slot> _slots = [];
  int? _selected;
  EditMode _mode = EditMode.select;
  bool _dirty = false;
  bool _geometryChanged = false;
  bool _busy = false;
  bool _showCars = true;
  DetectionResult? _result;
  List<ModelFile> _models = [];
  String? _model;
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([api.photo(widget.photoId), api.models(), api.settings()]);
      final photo = results[0] as Photo;
      final models = results[1] as List<ModelFile>;
      final settings = results[2] as Settings;
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _models = models;
        _model = models.any((m) => m.name == settings.model)
            ? settings.model
            : (models.isEmpty ? null : models.first.name);
        _resetSlots(photo);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _resetSlots(Photo photo) {
    _slots = photo.slots.map((s) => s.copy()).toList();
    final last = photo.lastResult;
    _result = last != null && last.statuses.length == _slots.length ? last : null;
    _dirty = false;
    _geometryChanged = false;
    _select(null);
  }

  void _select(int? i) {
    _selected = i;
    _labelController.text = i == null ? '' : _slots[i].label;
  }

  String _nextLabel() {
    var max = 0;
    for (final s in _slots) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(s.label);
      if (m != null) max = [max, int.parse(m.group(1)!)].reduce((a, b) => a > b ? a : b);
    }
    return 'Slot A${max + 1}';
  }

  void _geometryEdited() {
    _dirty = true;
    _geometryChanged = true;
    _result = null;
  }

  void _addSlot(Rect rect) => setState(() {
        _slots.add(Slot(label: _nextLabel(), rect: rect));
        _select(_slots.length - 1);
        _geometryEdited();
      });

  void _changeSlot(int i, Rect rect) => setState(() {
        _slots[i].rect = rect;
        _geometryEdited();
      });

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      _slots.removeAt(i);
      _select(null);
      _geometryEdited();
    });
  }

  Future<void> _clearAll() async {
    if (_slots.isEmpty) return;
    if (!await confirm(context, 'Hapus semua slot?', 'Semua ${_slots.length} slot di foto ini akan dihapus. '
        'Perubahan baru tersimpan setelah menekan "Simpan".')) {
      return;
    }
    setState(() {
      _slots.clear();
      _select(null);
      _geometryEdited();
    });
  }

  Future<bool> _save({bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      final keepResult = !_geometryChanged ? _result : null;
      final photo = await api.saveSlots(widget.photoId, _slots);
      if (!mounted) return false;
      setState(() {
        final selected = _selected;
        _photo = photo;
        _resetSlots(photo);
        _result = keepResult;
        if (selected != null && selected < _slots.length) _select(selected);
      });
      if (!quiet) showMessage(context, 'Konfigurasi ${_slots.length} slot disimpan');
      return true;
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detect() async {
    if (_slots.isEmpty) {
      showMessage(context, 'Tambahkan minimal satu slot dulu (mode "Gambar slot").', error: true);
      return;
    }
    if (_dirty && !await _save(quiet: true)) return;
    setState(() => _busy = true);
    try {
      final result = await api.detect(widget.photoId, model: _model);
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!_dirty || await confirm(context, 'Buang perubahan?', 'Perubahan slot belum disimpan.', action: 'Buang')) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (_dirty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Simpan'),
                ),
              ),
          ],
          bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
        ),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : photo == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final editor = _editor(photo);
                    final panel = _panel();
                    if (c.maxWidth >= 900) {
                      return Row(children: [
                        Expanded(child: editor),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 340, child: panel),
                      ]);
                    }
                    return Column(children: [
                      Expanded(flex: 3, child: editor),
                      const Divider(height: 1),
                      Expanded(flex: 2, child: panel),
                    ]);
                  }),
      ),
    );
  }

  Widget _editor(Photo photo) {
    final hint = _mode == EditMode.draw
        ? 'Tarik (klik & geser) di foto untuk membuat slot baru.'
        : 'Klik slot untuk memilih. Geser untuk memindah, tarik sudut untuk mengubah ukuran.';
    // Tinggi toolbar dibuat tetap supaya foto tidak bergeser saat mode diganti.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          SegmentedButton<EditMode>(
            segments: const [
              ButtonSegment(value: EditMode.select, icon: Icon(Icons.pan_tool_alt_outlined), label: Text('Pilih / ubah')),
              ButtonSegment(value: EditMode.draw, icon: Icon(Icons.crop_square), label: Text('Gambar slot')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          const Spacer(),
          Switch(value: _showCars, onChanged: _result == null ? null : (v) => setState(() => _showCars = v)),
          const SizedBox(width: 6),
          const Text('Kotak mobil'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFF1E1F22),
          padding: const EdgeInsets.all(16),
          child: SlotCanvas(
            imageUrl: api.photoImageUrl(photo.id),
            imageSize: photo.size,
            slots: _slots,
            selected: _selected,
            mode: _mode,
            statuses: _result?.statuses,
            cars: _result != null && _showCars ? _result!.cars : const [],
            onSelect: (i) => setState(() => _select(i)),
            onAdd: _addSlot,
            onChange: _changeSlot,
          ),
        ),
      ),
    ]);
  }

  Widget _panel() {
    final theme = Theme.of(context);
    final result = _result;
    final selected = _selected;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Deteksi', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      DropdownButton<String>(
        isExpanded: true,
        value: _model,
        hint: const Text('Tidak ada model di folder'),
        items: [
          for (final m in _models) DropdownMenuItem(value: m.name, child: Text('${m.name}  (${m.sizeMb} MB)')),
        ],
        onChanged: (v) => setState(() => _model = v),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy || _model == null ? null : _detect,
        icon: const Icon(Icons.play_arrow),
        label: Text(_dirty ? 'Simpan & jalankan deteksi' : 'Jalankan deteksi'),
      ),
      const SizedBox(height: 12),
      if (result != null) ...[
        SummaryChips(summary: result.summary),
        const SizedBox(height: 6),
        Text('Model ${result.model} · ${result.cars.length} mobil terdeteksi · ${result.elapsedMs} ms',
            style: theme.textTheme.bodySmall),
        if (result.warning != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(result.warning!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
          ),
      ] else
        Text(_slots.isEmpty ? 'Belum ada slot.' : 'Belum ada hasil untuk konfigurasi ini.',
            style: theme.textTheme.bodySmall),
      const Divider(height: 32),
      Row(children: [
        Expanded(child: Text('Slot parkir (${_slots.length})', style: theme.textTheme.titleMedium)),
        TextButton(onPressed: _slots.isEmpty ? null : _clearAll, child: const Text('Hapus semua')),
      ]),
      if (selected != null && selected < _slots.length) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(labelText: 'Nama slot', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() {
            _slots[selected].label = v;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(_coords(_slots[selected].rect), style: theme.textTheme.bodySmall),
          ),
          TextButton.icon(onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline), label: const Text('Hapus slot')),
        ]),
      ],
      const SizedBox(height: 4),
      for (var i = 0; i < _slots.length; i++)
        ListTile(
          dense: true,
          selected: i == selected,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: statusColors[result?.statuses[i]] ?? const Color(0xFF3B6EF0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          title: Text(_slots[i].label.isEmpty ? '(tanpa nama)' : _slots[i].label),
          subtitle: Text(_coords(_slots[i].rect)),
          trailing: result == null ? null : Text(statusLabels[result.statuses[i]] ?? ''),
          onTap: () => setState(() => _select(i)),
        ),
      if (_dirty) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _resetSlots(_photo!)),
          child: const Text('Batalkan perubahan'),
        ),
      ],
    ]);
  }

  String _coords(Rect r) =>
      'x ${r.left.round()}–${r.right.round()}, y ${r.top.round()}–${r.bottom.round()}';
}
