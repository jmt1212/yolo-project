import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;

/// Klien untuk backend FastAPI (backend/main.py).
class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  String photoImageUrl(String photoId) => '$baseUrl/api/photos/$photoId/image';

  Future<dynamic> _send(Future<http.Response> request) async {
    final http.Response res;
    try {
      res = await request.timeout(const Duration(seconds: 120));
    } catch (_) {
      throw ApiException('Tidak dapat terhubung ke server ($baseUrl)');
    }
    if (res.statusCode >= 400) {
      var message = 'Server mengembalikan error ${res.statusCode}';
      try {
        final detail = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
        if (detail is String) message = detail;
      } catch (_) {}
      throw ApiException(message);
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Map<String, String> get _json => {'Content-Type': 'application/json'};

  Future<void> health() => _send(http.get(_uri('/api/health')));

  // Gedung
  Future<List<Building>> buildings() async {
    final data = await _send(http.get(_uri('/api/buildings'))) as List;
    return data.map((e) => Building.fromJson(e)).toList();
  }

  Future<Building> building(String id) async => Building.fromJson(await _send(http.get(_uri('/api/buildings/$id'))));

  Future<Building> addBuilding(String name, String location) async => Building.fromJson(
    await _send(
      http.post(_uri('/api/buildings'), headers: _json, body: jsonEncode({'name': name, 'location': location})),
    ),
  );

  Future<Building> updateBuilding(String id, {String? name, String? location, String? layoutPhotoId}) async =>
      Building.fromJson(
        await _send(
          http.patch(
            _uri('/api/buildings/$id'),
            headers: _json,
            body: jsonEncode({'name': ?name, 'location': ?location, 'layout_photo_id': ?layoutPhotoId}),
          ),
        ),
      );

  Future<void> deleteBuilding(String id) => _send(http.delete(_uri('/api/buildings/$id')));

  // Foto
  Future<List<Photo>> photos(String buildingId) async {
    final data = await _send(http.get(_uri('/api/buildings/$buildingId/photos'))) as List;
    return data.map((e) => Photo.fromJson(e)).toList();
  }

  Future<Photo> photo(String id) async => Photo.fromJson(await _send(http.get(_uri('/api/photos/$id'))));

  Future<Photo> uploadPhoto(String buildingId, String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', _uri('/api/buildings/$buildingId/photos'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return Photo.fromJson(await _send(req.send().then(http.Response.fromStream)));
  }

  Future<void> deletePhoto(String id) => _send(http.delete(_uri('/api/photos/$id')));

  Future<Photo> saveSlots(String photoId, List<Slot> slots) async => Photo.fromJson(
    await _send(
      http.put(
        _uri('/api/photos/$photoId/slots'),
        headers: _json,
        body: jsonEncode({'slots': slots.map((s) => s.toJson()).toList()}),
      ),
    ),
  );

  Future<Layout> layout(String buildingId) async =>
      Layout.fromJson(await _send(http.get(_uri('/api/buildings/$buildingId/layout'))));

  Future<DetectionResult> detectWithSlots(String photoId, List<Slot> slots) async => DetectionResult.fromJson(
    await _send(
      http.post(
        _uri('/api/photos/$photoId/detect'),
        headers: _json,
        body: jsonEncode({'slots': slots.map((s) => s.toJson()).toList()}),
      ),
    ),
  );

  Future<DetectionResult> detect(String photoId, {String? model}) async => DetectionResult.fromJson(
    await _send(http.post(_uri('/api/photos/$photoId/detect'), headers: _json, body: jsonEncode({'model': ?model}))),
  );

  // Model & pengaturan
  Future<Settings> settings() async => Settings.fromJson(await _send(http.get(_uri('/api/settings'))));

  Future<Settings> updateSettings({String? modelDir, String? model, double? conf, double? overlap}) async =>
      Settings.fromJson(
        await _send(
          http.put(
            _uri('/api/settings'),
            headers: _json,
            body: jsonEncode({'model_dir': ?modelDir, 'model': ?model, 'conf': ?conf, 'overlap': ?overlap}),
          ),
        ),
      );

  Future<List<ModelFile>> models() async {
    final data = await _send(http.get(_uri('/api/models')));
    return (data['models'] as List).map((e) => ModelFile.fromJson(e)).toList();
  }

  Future<BrowseResult> browse([String? path]) async =>
      BrowseResult.fromJson(await _send(http.get(_uri('/api/browse', path == null ? null : {'path': path}))));
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Building {
  Building({
    required this.id,
    required this.name,
    required this.location,
    required this.photoCount,
    required this.lotCount,
    required this.layoutPhotoId,
  });
  final String id;
  final String name;
  final String location;
  final int photoCount;
  final int lotCount; // jumlah slot di foto acuan
  final String? layoutPhotoId;

  /// Kode singkat gedung untuk kotak huruf dan nama lot: "Gedung T" -> "T", "Perpustakaan" -> "P".
  String get code {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length > 1 && words.first.toLowerCase() == 'gedung') {
      final w = words[1].toUpperCase();
      return w.length > 3 ? w.substring(0, 3) : w;
    }
    return words.first.isEmpty ? '?' : words.first[0].toUpperCase();
  }

  factory Building.fromJson(Map<String, dynamic> j) => Building(
    id: j['id'],
    name: j['name'],
    location: j['location'] ?? '',
    photoCount: j['photo_count'] ?? 0,
    lotCount: j['lot_count'] ?? 0,
    layoutPhotoId: j['layout_photo_id'],
  );
}

class Slot {
  Slot({required this.label, required this.rect});
  String label;
  Rect rect; // koordinat piksel pada foto asli

  factory Slot.fromJson(Map<String, dynamic> j) {
    final b = (j['bbox'] as List).map((v) => (v as num).toDouble()).toList();
    return Slot(label: j['label'], rect: Rect.fromLTRB(b[0], b[1], b[2], b[3]));
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'bbox': [rect.left, rect.top, rect.right, rect.bottom],
  };

  Slot copy() => Slot(label: label, rect: rect);
}

class Photo {
  Photo({
    required this.id,
    required this.originalName,
    required this.width,
    required this.height,
    required this.slots,
    required this.lastResult,
  });
  final String id;
  final String originalName;
  final int width;
  final int height;
  final List<Slot> slots;
  final DetectionResult? lastResult;

  Size get size => Size(width.toDouble(), height.toDouble());

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
    id: j['id'],
    originalName: j['original_name'] ?? '',
    width: j['width'],
    height: j['height'],
    slots: (j['slots'] as List).map((e) => Slot.fromJson(e)).toList(),
    lastResult: j['last_result'] == null ? null : DetectionResult.fromJson(j['last_result']),
  );
}

/// Lot dari foto acuan gedung beserta ukuran foto acuannya.
class Layout {
  Layout({required this.size, required this.slots});
  final Size? size; // null jika gedung belum punya foto acuan
  final List<Slot> slots;

  factory Layout.fromJson(Map<String, dynamic> j) => Layout(
    size: j['width'] == null ? null : Size((j['width'] as num).toDouble(), (j['height'] as num).toDouble()),
    slots: (j['slots'] as List).map((e) => Slot.fromJson(e)).toList(),
  );

  /// Lot yang diskalakan ke ukuran foto lain (kamera dan sudut dianggap sama).
  List<Slot> scaledTo(Size target) {
    final src = size;
    if (src == null) return [];
    final sx = target.width / src.width, sy = target.height / src.height;
    return [
      for (final s in slots)
        Slot(
          label: s.label,
          rect: Rect.fromLTRB(s.rect.left * sx, s.rect.top * sy, s.rect.right * sx, s.rect.bottom * sy),
        ),
    ];
  }

  /// True jika rasio foto berbeda dari foto acuan (posisi lot perlu diperiksa).
  bool aspectDiffers(Size target) {
    final src = size;
    if (src == null) return false;
    final sx = target.width / src.width, sy = target.height / src.height;
    return (sx - sy).abs() / (sx > sy ? sx : sy) > 0.03;
  }
}

class Summary {
  Summary(this.total, this.empty, this.occupied, this.anomaly);
  final int total, empty, occupied, anomaly;
  factory Summary.fromJson(Map<String, dynamic> j) => Summary(j['total'], j['empty'], j['occupied'], j['anomaly']);
}

class SlotResult {
  SlotResult({required this.label, required this.rect, required this.status});
  final String label;
  final Rect rect;
  final String status; // empty / occupied / anomaly
}

class DetectionResult {
  DetectionResult({
    required this.model,
    required this.summary,
    required this.slots,
    required this.cars,
    required this.elapsedMs,
    required this.warning,
    required this.layoutSource,
    required this.layoutWarning,
  });
  final String model;
  final Summary summary;
  final List<SlotResult> slots;
  final List<Rect> cars;
  final int elapsedMs;
  final String? warning; // mis. model tanpa kelas mobil
  final String layoutSource; // photo / building / none
  final String? layoutWarning;

  List<String> get statuses => slots.map((s) => s.status).toList();

  static Rect _rect(List bbox) {
    final b = bbox.map((v) => (v as num).toDouble()).toList();
    return Rect.fromLTRB(b[0], b[1], b[2], b[3]);
  }

  factory DetectionResult.fromJson(Map<String, dynamic> j) => DetectionResult(
    model: j['model'],
    summary: Summary.fromJson(j['summary']),
    slots: (j['slots'] as List)
        .map((s) => SlotResult(label: s['label'], rect: _rect(s['bbox']), status: s['status']))
        .toList(),
    cars: (j['cars'] as List).map((c) => _rect(c['bbox'])).toList(),
    elapsedMs: j['elapsed_ms'] ?? 0,
    warning: j['warning'],
    layoutSource: j['layout_source'] ?? 'photo',
    layoutWarning: j['layout_warning'],
  );
}

class Settings {
  Settings({required this.modelDir, required this.model, required this.conf, required this.overlap});
  final String modelDir;
  final String model;
  final double conf;
  final double overlap;

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    modelDir: j['model_dir'],
    model: j['model'],
    conf: (j['conf'] as num).toDouble(),
    overlap: (j['overlap'] as num).toDouble(),
  );
}

class ModelFile {
  ModelFile(this.name, this.sizeMb);
  final String name;
  final double sizeMb;
  factory ModelFile.fromJson(Map<String, dynamic> j) => ModelFile(j['name'], (j['size_mb'] as num).toDouble());
}

class BrowseResult {
  BrowseResult({required this.path, required this.parent, required this.dirs, required this.models});
  final String path;
  final String? parent;
  final List<String> dirs;
  final List<ModelFile> models;

  factory BrowseResult.fromJson(Map<String, dynamic> j) => BrowseResult(
    path: j['path'],
    parent: j['parent'],
    dirs: List<String>.from(j['dirs']),
    models: (j['models'] as List).map((e) => ModelFile.fromJson(e)).toList(),
  );
}
