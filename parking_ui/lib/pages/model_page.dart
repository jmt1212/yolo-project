import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';

/// Pilih folder model (.pt), model aktif, ambang deteksi, dan alamat server.
class ModelPage extends StatefulWidget {
  const ModelPage({super.key});

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage> {
  Settings? _settings;
  BrowseResult? _browse;
  String? _error;
  bool _busy = false;
  double _conf = 0.35;
  double _overlap = 0.30;
  final _pathController = TextEditingController();
  final _serverController = TextEditingController(text: api.baseUrl);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final settings = await api.settings();
      final browse = await api.browse(settings.modelDir);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _conf = settings.conf;
        _overlap = settings.overlap;
        _showFolder(browse);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _showFolder(BrowseResult browse) {
    _browse = browse;
    _pathController.text = browse.path;
  }

  Future<void> _open(String path) async {
    try {
      final browse = await api.browse(path);
      if (mounted) setState(() => _showFolder(browse));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _apply(Future<Settings> Function() update, String success) async {
    setState(() => _busy = true);
    try {
      final settings = await update();
      if (!mounted) return;
      setState(() => _settings = settings);
      showMessage(context, success);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useModel(String folder, String model) =>
      _apply(() => api.updateSettings(modelDir: folder, model: model), 'Model aktif: $model');

  void _saveThresholds() => _apply(() => api.updateSettings(conf: _conf, overlap: _overlap), 'Ambang deteksi disimpan');

  Future<void> _saveServer() async {
    final url = _serverController.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    final previous = api.baseUrl;
    api.baseUrl = url;
    try {
      await api.health();
      if (mounted) showMessage(context, 'Terhubung ke $url');
      await _load();
    } on ApiException catch (e) {
      api.baseUrl = previous;
      _serverController.text = previous;
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final browse = _browse;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Model'),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : settings == null || browse == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.check_circle, color: Color(0xFF2E9E5B)),
                        title: Text(settings.model.isEmpty ? '(belum ada model)' : 'Model aktif: ${settings.model}'),
                        subtitle: Text(settings.modelDir),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Folder model', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Folder di komputer server yang berisi file model YOLO (.pt).',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pathController,
                            decoration: const InputDecoration(
                              labelText: 'Lokasi folder',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: _open,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: () => _open(_pathController.text), child: const Text('Buka')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          if (browse.parent != null)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.arrow_upward),
                              title: const Text('Folder induk'),
                              onTap: () => _open(browse.parent!),
                            ),
                          for (final dir in browse.dirs)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(dir),
                              onTap: () => _open('${browse.path}\\$dir'),
                            ),
                          if (browse.dirs.isEmpty && browse.parent == null)
                            const ListTile(dense: true, title: Text('Tidak ada subfolder')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Model di folder ini (${browse.models.length})', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    if (browse.models.isEmpty)
                      Text('Tidak ada file .pt di folder ini.', style: theme.textTheme.bodySmall)
                    else
                      for (final m in browse.models)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.memory),
                            title: Text(m.name),
                            subtitle: Text('${m.sizeMb} MB'),
                            selected: settings.modelDir == browse.path && settings.model == m.name,
                            trailing: settings.modelDir == browse.path && settings.model == m.name
                                ? const Chip(label: Text('Aktif'))
                                : FilledButton.tonal(
                                    onPressed: _busy ? null : () => _useModel(browse.path, m.name),
                                    child: const Text('Gunakan'),
                                  ),
                          ),
                        ),
                    const Divider(height: 40),
                    Text('Ambang deteksi', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _slider(
                      'Confidence minimum',
                      'Kotak mobil dengan keyakinan di bawah nilai ini diabaikan.',
                      _conf,
                      (v) => setState(() => _conf = v),
                    ),
                    _slider(
                      'Batas overlap slot',
                      'Mobil dihitung masuk slot jika menutupi lebih dari nilai ini dari luas slot.',
                      _overlap,
                      (v) => setState(() => _overlap = v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy || (_conf == settings.conf && _overlap == settings.overlap)
                            ? null
                            : _saveThresholds,
                        child: const Text('Simpan ambang'),
                      ),
                    ),
                    const Divider(height: 40),
                    Text('Alamat server', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _serverController,
                            decoration: const InputDecoration(
                              labelText: 'URL backend',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveServer(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: _saveServer, child: const Text('Hubungkan')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _slider(String title, String help, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text('${(value * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(value: value, min: 0.05, max: 0.95, divisions: 18, onChanged: onChanged),
        Text(help, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
    );
  }
}
