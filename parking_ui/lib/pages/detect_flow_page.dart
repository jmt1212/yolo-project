import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets/petra.dart';
import '../widgets/slot_canvas.dart';

/// Tahap alur deteksi, sesuai frame 02–07 di wireframe.
enum _Stage { pick, ready, processing, result, empty, failed }

const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};

/// Langkah 2–3: unggah foto untuk satu gedung lalu tampilkan hasil deteksinya.
class DetectFlowPage extends StatefulWidget {
  const DetectFlowPage({super.key, required this.building});
  final Building building;

  @override
  State<DetectFlowPage> createState() => _DetectFlowPageState();
}

class _DetectFlowPageState extends State<DetectFlowPage> {
  _Stage _stage = _Stage.pick;

  // Foto yang dipilih (belum tentu sudah diunggah).
  Uint8List? _bytes;
  String _fileName = '';
  String? _formatError;
  bool _dragging = false;

  // Lot pada foto ini, bisa diatur manual (awalnya dari foto acuan gedung).
  Size? _imageSize;
  Layout? _layout;
  List<Slot> _slots = [];
  int? _selected;
  EditMode _mode = EditMode.select;
  final _labelController = TextEditingController();

  Photo? _uploaded; // diisi setelah foto diterima server
  bool _uploadDone = false;
  DetectionResult? _result;
  String? _failure;
  bool _failureIsConnection = false;
  int _run = 0; // dinaikkan saat deteksi dibatalkan supaya hasil lama diabaikan

  Building get b => widget.building;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- aksi

  Future<void> _accept(String name, Uint8List bytes) async {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!_allowedExt.contains(ext)) {
      setState(() {
        _formatError = 'Format tidak didukung. Gunakan JPG, PNG, atau WEBP.';
        _stage = _Stage.pick;
      });
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = name;
      _formatError = null;
      _uploaded = null;
      _result = null;
      _imageSize = null;
      _slots = [];
      _select(null);
      _stage = _Stage.ready;
    });
    // Ukuran asli foto + lot dari foto acuan, untuk diisi awal di editor lot.
    final Size size;
    try {
      final image = await decodeImageFromList(bytes);
      size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
    } catch (_) {
      if (mounted) setState(() => _formatError = 'Foto tidak dapat dibaca. Coba foto lain.');
      if (mounted) setState(() => _stage = _Stage.pick);
      return;
    }
    Layout? layout;
    try {
      layout = await api.layout(b.id);
    } on ApiException {
      layout = null;
    }
    if (!mounted || _bytes != bytes) return;
    setState(() {
      _imageSize = size;
      _layout = layout;
      _slots = layout?.scaledTo(size) ?? [];
    });
  }

  void _select(int? i) {
    _selected = i;
    _labelController.text = i == null ? '' : _slots[i].label;
  }

  void _lotsEdited() => _result = null;

  void _addSlot(Rect rect) => setState(() {
    _slots.add(Slot(label: nextSlotLabel(_slots, b.code), rect: rect));
    _select(_slots.length - 1);
    _lotsEdited();
  });

  void _changeSlot(int i, Rect rect) => setState(() {
    _slots[i].rect = rect;
    _lotsEdited();
  });

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      _slots.removeAt(i);
      _select(null);
      _lotsEdited();
    });
  }

  void _resetLots() => setState(() {
    _slots = _layout?.scaledTo(_imageSize!) ?? [];
    _select(null);
    _lotsEdited();
  });

  /// Dari halaman hasil: kembali ke editor lot dengan foto yang sama.
  void _editLots() => setState(() {
    _select(null);
    _mode = EditMode.select;
    _stage = _Stage.ready;
  });

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExt.toList(),
      dialogTitle: 'Pilih foto parkiran',
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    _accept(file.name, await file.readAsBytes());
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (details.files.isEmpty) return;
    final file = details.files.first;
    _accept(file.name, await file.readAsBytes());
  }

  void _resetPhoto() => setState(() {
    _bytes = null;
    _fileName = '';
    _uploaded = null;
    _result = null;
    _formatError = null;
    _imageSize = null;
    _slots = [];
    _select(null);
    _stage = _Stage.pick;
  });

  Future<void> _detect() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final run = ++_run;
    setState(() {
      _stage = _Stage.processing;
      _uploadDone = _uploaded != null;
    });
    try {
      _uploaded ??= await api.uploadPhoto(b.id, _fileName, bytes);
      if (run != _run) return;
      setState(() => _uploadDone = true);
      final result = await api.detectWithSlots(_uploaded!.id, _slots);
      if (run != _run || !mounted) return;
      setState(() {
        _result = result;
        // Pakai lot versi server (sudah dirapikan) supaya urutannya sama dengan hasil.
        _slots = [for (final s in result.slots) Slot(label: s.label, rect: s.rect)];
        if (result.warning != null) {
          _fail(result.warning!, connection: false);
        } else {
          _stage = result.summary.total == 0 ? _Stage.empty : _Stage.result;
        }
      });
    } on ApiException catch (e) {
      if (run != _run || !mounted) return;
      setState(() => _fail(e.message, connection: e.message.startsWith('Tidak dapat terhubung')));
    }
  }

  void _fail(String message, {required bool connection}) {
    _failure = message;
    _failureIsConnection = connection;
    _stage = _Stage.failed;
  }

  void _cancel() => setState(() {
    _run++;
    _stage = _Stage.ready;
  });

  void _changeBuilding() => Navigator.pop(context);

  // ---------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_stage) {
      _Stage.pick => (
        'Unggah foto parkir',
        'Pilih satu foto area parkir untuk mendeteksi lot yang tersedia di ${b.name}.',
      ),
      _Stage.ready => (
        'Foto siap untuk dideteksi',
        'Periksa foto dan posisi lot sebelum memulai deteksi. Geser atau ubah ukuran kotak lot bila perlu.',
      ),
      _Stage.processing => (
        'Sedang mendeteksi lot parkir',
        'Foto Anda sedang dianalisis. Hasil akan ditampilkan setelah proses selesai.',
      ),
      _Stage.result => (
        'Hasil deteksi parkir ${b.name}',
        'Deteksi selesai. Ketersediaan berikut hanya berdasarkan foto yang Anda unggah.',
      ),
      _Stage.empty => (
        'Belum ada lot yang terdeteksi',
        'Proses selesai, tetapi sistem belum dapat mengenali lot parkir pada foto ${b.name}.',
      ),
      _Stage.failed => (
        'Foto belum berhasil diproses',
        'Terjadi kendala saat mendeteksi parkir di ${b.name}. Belum ada hasil yang tersedia.',
      ),
    };
    final step = _stage == _Stage.result || _stage == _Stage.empty ? 3 : 2;
    return PetraShell(
      step: step,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(title: title, subtitle: subtitle),
          const SizedBox(height: 20),
          SelectedBuildingBar(building: b, onChange: _changeBuilding),
          const SizedBox(height: 16),
          switch (_stage) {
            _Stage.pick => _pickView(),
            _Stage.ready => _readyView(),
            _Stage.processing => _processingView(),
            _Stage.result => _resultView(),
            _Stage.empty => _emptyView(),
            _Stage.failed => _failedView(),
          },
        ],
      ),
    );
  }

  // 02 · Unggah foto
  Widget _pickView() {
    return TwoColumn(
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: _onDrop,
            child: CustomPaint(
              painter: _DashedBorder(color: _formatError != null ? Pk.error : Pk.faint),
              child: Container(
                color: _dragging ? Pk.fill : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
                child: Column(
                  children: [
                    const Icon(Icons.arrow_upward, color: Pk.muted, size: 26),
                    const SizedBox(height: 14),
                    const Text(
                      'Tarik dan lepas foto di sini',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text('atau pilih foto dari perangkat Anda', style: TextStyle(fontSize: 12, color: Pk.muted)),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: _pickFile, child: const Text('Pilih foto')),
                    const SizedBox(height: 12),
                    const Text('1 foto · JPG, PNG, WEBP', style: TextStyle(fontSize: 11, color: Pk.faint)),
                    if (_formatError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _formatError!,
                        style: const TextStyle(fontSize: 12, color: Pk.error, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(
                child: Text('Belum ada foto yang dipilih', style: TextStyle(fontSize: 12, color: Pk.muted)),
              ),
              FilledButton(onPressed: null, child: Text('Deteksi parkir')),
            ],
          ),
        ],
      ),
      side: TipsPanel(buildingName: b.name),
    );
  }

  // 03 · Foto siap diproses
  Widget _readyView() {
    final ext = _fileName.split('.').last.toUpperCase();
    return TwoColumn(
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lotEditor(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fileName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      '$ext · ${_formatSize(_bytes!.length)} · Foto valid',
                      style: const TextStyle(fontSize: 11, color: Pk.muted),
                    ),
                  ],
                ),
              ),
              LinkText('Ganti foto', onTap: _pickFile),
              const SizedBox(width: 16),
              LinkText('Hapus foto', onTap: _resetPhoto),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _imageSize != null && _slots.isEmpty ? 'Tambahkan minimal satu lot untuk memulai deteksi.' : '',
                  style: const TextStyle(fontSize: 12, color: Pk.muted),
                ),
              ),
              FilledButton(
                onPressed: _imageSize == null || _slots.isEmpty ? null : _detect,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('Deteksi parkir'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 16)],
                ),
              ),
            ],
          ),
        ],
      ),
      side: TipsPanel(buildingName: b.name),
    );
  }

  /// Foto dengan kotak lot yang bisa digambar, dipindah, diubah ukurannya, diganti nama, dan dihapus.
  Widget _lotEditor() {
    final size = _imageSize;
    final selected = _selected;
    final hint = _mode == EditMode.draw
        ? 'Tarik di foto untuk menambah lot baru.'
        : 'Klik lot untuk memilih. Geser untuk memindah, tarik sudut untuk mengubah ukuran.';
    final hasLayout = _layout?.size != null;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<EditMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
                  selectedBackgroundColor: Pk.dark,
                  selectedForegroundColor: Colors.white,
                  side: const BorderSide(color: Pk.line),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: EditMode.select,
                    icon: Icon(Icons.pan_tool_alt_outlined, size: 16),
                    label: Text('Pilih / ubah', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: EditMode.draw,
                    icon: Icon(Icons.crop_square, size: 16),
                    label: Text('Gambar lot', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              Text('${_slots.length} lot', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (hasLayout) LinkText('Kembalikan ke tata letak ${b.name}', onTap: _resetLots),
            ],
          ),
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(fontSize: 11, color: Pk.muted)),
          const SizedBox(height: 10),
          Container(
            height: 340,
            color: Pk.fill,
            padding: const EdgeInsets.all(10),
            child: size == null
                ? const Center(child: CircularProgressIndicator())
                : SlotCanvas(
                    imageUrl: '',
                    imageBytes: _bytes,
                    imageSize: size,
                    slots: _slots,
                    selected: selected,
                    mode: _mode,
                    onSelect: (i) => setState(() => _select(i)),
                    onAdd: _addSlot,
                    onChange: _changeSlot,
                  ),
          ),
          if (size != null && !hasLayout) ...[
            const SizedBox(height: 10),
            _InfoBox(
              text:
                  '${b.name} belum memiliki tata letak lot. Pilih mode "Gambar lot", lalu tarik kotak '
                  'di setiap lot parkir pada foto.',
            ),
          ] else if (size != null && _layout!.aspectDiffers(size)) ...[
            const SizedBox(height: 10),
            const _InfoBox(
              text:
                  'Ukuran foto berbeda dengan foto acuan gedung, jadi posisi lot mungkin bergeser. '
                  'Periksa dan sesuaikan kotak lot sebelum deteksi.',
            ),
          ],
          if (selected != null && selected < _slots.length) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _labelController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Nama lot', isDense: true),
                    onChanged: (v) => setState(() => _slots[selected].label = v),
                  ),
                ),
                const SizedBox(width: 16),
                LinkText('Hapus lot', onTap: _deleteSelected),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 04 · Proses deteksi
  Widget _processingView() {
    Widget item(String text, String state) {
      final (icon, weight, color) = switch (state) {
        'done' => (Icons.check, FontWeight.w400, Pk.muted),
        'active' => (Icons.more_horiz, FontWeight.w700, Pk.ink),
        _ => (Icons.remove, FontWeight.w400, Pk.faint),
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(fontSize: 12, fontWeight: weight, color: color),
            ),
          ],
        ),
      );
    }

    return _SplitPanel(
      left: _photoWithCaption('$_fileName · ${_formatSize(_bytes!.length)}'),
      right: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProgressDots(),
          const SizedBox(height: 18),
          const Text('Menganalisis foto...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Sistem mengenali posisi lot dan memeriksa apakah setiap lot terisi kendaraan.',
            style: TextStyle(fontSize: 12, color: Pk.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          item(_uploadDone ? 'Foto diterima' : 'Mengunggah foto', _uploadDone ? 'done' : 'active'),
          item('Mendeteksi lot dan kendaraan', _uploadDone ? 'active' : 'pending'),
          item('Menyiapkan ringkasan hasil', 'pending'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              const FilledButton(onPressed: null, child: Text('Memproses...')),
              OutlinedButton(onPressed: _cancel, child: const Text('Batalkan')),
            ],
          ),
        ],
      ),
    );
  }

  // 05 · Hasil deteksi
  Widget _resultView() {
    final r = _result!;
    final photo = _uploaded!;
    final emptyLabels = [
      for (final s in r.slots)
        if (s.status == 'empty') s.label,
    ];
    return TwoColumn(
      sideWidth: 300,
      main: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Posisi lot terdeteksi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                LinkText('Ubah posisi lot', onTap: _editLots),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              color: Pk.fill,
              padding: const EdgeInsets.all(12),
              height: 320,
              child: SlotCanvas.result(
                imageBytes: _bytes,
                imageSize: photo.size,
                slots: [for (final s in r.slots) Slot(label: s.label, rect: s.rect)],
                statuses: r.statuses,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in r.slots) _LotTile(slot: s)]),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(fill: statusColors['empty']!, label: 'Lot kosong'),
                _Legend(fill: statusColors['occupied']!, label: 'Lot terisi'),
                _Legend(fill: statusColors['anomaly']!, label: 'Anomali (lebih dari satu kendaraan)'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Sumber: $_fileName · Kode lot mengikuti konfigurasi ${b.name}.',
              style: const TextStyle(fontSize: 11, color: Pk.muted),
            ),
          ],
        ),
      ),
      side: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ringkasan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(value: r.summary.total, label: 'Total lot'),
                const SizedBox(width: 8),
                _Stat(value: r.summary.empty, label: 'Kosong', color: statusColors['empty']),
                const SizedBox(width: 8),
                _Stat(value: r.summary.occupied, label: 'Terisi', color: statusColors['occupied']),
              ],
            ),
            if (r.summary.anomaly > 0) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 2, right: 6),
                    color: statusColors['anomaly'],
                  ),
                  Expanded(
                    child: Text(
                      '${r.summary.anomaly} lot anomali: terdeteksi lebih dari satu kendaraan.',
                      style: const TextStyle(fontSize: 11, color: Pk.muted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text('Lot kosong terdeteksi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              emptyLabels.isEmpty ? 'Tidak ada lot kosong.' : emptyLabels.join(', '),
              style: const TextStyle(fontSize: 12, color: Pk.muted),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kondisi dapat berubah setelah foto diambil. Periksa kembali area parkir saat tiba.',
              style: TextStyle(fontSize: 11, color: Pk.muted, height: 1.4),
            ),
            if (r.layoutWarning != null) ...[const SizedBox(height: 10), _InfoBox(text: r.layoutWarning!)],
            const SizedBox(height: 16),
            FilledButton(onPressed: _resetPhoto, child: const Text('Unggah foto baru')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _editLots, child: const Text('Ubah posisi lot')),
          ],
        ),
      ),
    );
  }

  // 06 · Tidak ada lot terdeteksi
  Widget _emptyView() {
    final noLayout = _result?.layoutSource == 'none';
    return _SplitPanel(
      left: _photoWithCaption('$_fileName · ${_formatSize(_bytes!.length)}'),
      right: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TagLabel('0 LOT DIKENALI'),
          const SizedBox(height: 14),
          Text(
            noLayout ? 'Lot gedung ini belum diatur' : 'Coba gunakan foto yang lebih jelas',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            noLayout
                ? '${b.name} belum memiliki konfigurasi lot, sehingga foto belum bisa dicocokkan dengan posisi lot. '
                      'Admin dapat mengatur lot melalui menu Kelola.'
                : 'Garis lot mungkin tidak terlihat, foto terlalu gelap, atau area parkir tertutup objek. '
                      'Ambil ulang foto agar batas lot terlihat utuh.',
            style: const TextStyle(fontSize: 12, color: Pk.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          const _InfoBox(text: 'Hasil ini tidak berarti parkir penuh. Ketersediaan lot belum dapat disimpulkan.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(onPressed: _resetPhoto, child: const Text('Ganti foto')),
              OutlinedButton(onPressed: _detect, child: const Text('Coba lagi')),
            ],
          ),
        ],
      ),
    );
  }

  // 07 · Deteksi gagal
  Widget _failedView() {
    final reason = _failureIsConnection
        ? 'Koneksi terputus atau layanan deteksi sedang tidak merespons. Periksa koneksi internet Anda, lalu coba kembali.'
        : _failure ?? 'Layanan deteksi mengalami kendala.';
    return _SplitPanel(
      left: _photoWithCaption('$_fileName · Foto tetap tersimpan'),
      right: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Pk.fill,
              border: Border.all(color: Pk.line),
            ),
            child: const Text('!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 14),
          const Text('Deteksi tidak dapat diselesaikan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(reason, style: const TextStyle(fontSize: 12, color: Pk.muted, height: 1.4)),
          const SizedBox(height: 10),
          Text(
            'Anda tidak perlu mengunggah ulang foto untuk mencoba lagi. ${b.name} tetap terpilih.',
            style: const TextStyle(fontSize: 12, color: Pk.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(onPressed: _detect, child: const Text('Coba lagi')),
              OutlinedButton(onPressed: _resetPhoto, child: const Text('Ganti foto')),
            ],
          ),
          const SizedBox(height: 12),
          LinkText('Kembali ke pilih gedung', onTap: _changeBuilding),
        ],
      ),
    );
  }

  Widget _photoWithCaption(String caption) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PhotoBox(bytes: _bytes!, height: 240),
      const SizedBox(height: 8),
      Text(caption, style: const TextStyle(fontSize: 11, color: Pk.muted)),
    ],
  );
}

String _formatSize(int bytes) {
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  return '${(bytes / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Panel dua bagian: foto di kiri, keterangan di kanan (bertumpuk di layar sempit).
class _SplitPanel extends StatelessWidget {
  const _SplitPanel({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 20), right],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: left),
              const SizedBox(width: 24),
              Expanded(
                flex: 6,
                child: Padding(padding: const EdgeInsets.only(top: 8), child: right),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.bytes, required this.height});
  final Uint8List bytes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Pk.fill,
        border: Border.all(color: Pk.line),
      ),
      child: Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: Pk.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
            ),
            Text(label, style: const TextStyle(fontSize: 10, color: Pk.muted)),
          ],
        ),
      ),
    );
  }
}

/// Kotak kode lot (mis. "T-01 · Terisi"), seperti di frame hasil deteksi.
class _LotTile extends StatelessWidget {
  const _LotTile({required this.slot});
  final SlotResult slot;

  @override
  Widget build(BuildContext context) {
    final fg = statusTextColor(slot.status);
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(color: statusColors[slot.status] ?? Pk.fill),
      child: Column(
        children: [
          Text(
            slot.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
          const SizedBox(height: 2),
          Text(statusLabels[slot.status] ?? '', style: TextStyle(fontSize: 10, color: fg)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.fill, required this.label});
  final Color fill;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: fill),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Pk.muted)),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Pk.line),
        color: const Color(0xFFFAFAFA),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 15, color: Pk.ink),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }
}

/// Tiga kotak kecil yang bergantian menyala selama proses.
class _ProgressDots extends StatefulWidget {
  const _ProgressDots();

  @override
  State<_ProgressDots> createState() => _ProgressDotsState();
}

class _ProgressDotsState extends State<_ProgressDots> {
  int _active = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) => setState(() => _active = (_active + 1) % 3));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 6),
            color: i == _active ? Pk.dark : Pk.line,
          ),
      ],
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 6.0, gap = 5.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      for (double d = 0; d < total; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, total), paint);
      }
    }

    line(Offset.zero, Offset(size.width, 0));
    line(Offset(size.width, 0), Offset(size.width, size.height));
    line(Offset(size.width, size.height), Offset(0, size.height));
    line(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}
