import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;

/// Klien untuk backend FastAPI (backend/main.py).
class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

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

  Future<Building> addBuilding(String name) async => Building.fromJson(
      await _send(http.post(_uri('/api/buildings'), headers: _json, body: jsonEncode({'name': name}))));

  Future<void> renameBuilding(String id, String name) =>
      _send(http.patch(_uri('/api/buildings/$id'), headers: _json, body: jsonEncode({'name': name})));

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

  Future<Photo> saveSlots(String photoId, List<Slot> slots) async => Photo.fromJson(await _send(http.put(
      _uri('/api/photos/$photoId/slots'),
      headers: _json,
      body: jsonEncode({'slots': slots.map((s) => s.toJson()).toList()}))));

  Future<DetectionResult> detect(String photoId, {String? model}) async =>
      DetectionResult.fromJson(await _send(http.post(_uri('/api/photos/$photoId/detect'),
          headers: _json, body: jsonEncode({'model': ?model}))));

  // Model & pengaturan
  Future<Settings> settings() async => Settings.fromJson(await _send(http.get(_uri('/api/settings'))));

  Future<Settings> updateSettings({String? modelDir, String? model, double? conf, double? overlap}) async =>
      Settings.fromJson(await _send(http.put(_uri('/api/settings'),
          headers: _json,
          body: jsonEncode({
            'model_dir': ?modelDir,
            'model': ?model,
            'conf': ?conf,
            'overlap': ?overlap,
          }))));

  Future<List<ModelFile>> models() async {
    final data = await _send(http.get(_uri('/api/models')));
    return (data['models'] as List).map((e) => ModelFile.fromJson(e)).toList();
  }

  Future<BrowseResult> browse([String? path]) async => BrowseResult.fromJson(
      await _send(http.get(_uri('/api/browse', path == null ? null : {'path': path}))));
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Building {
  Building({required this.id, required this.name, required this.photoCount});
  final String id;
  final String name;
  final int photoCount;

  factory Building.fromJson(Map<String, dynamic> j) =>
      Building(id: j['id'], name: j['name'], photoCount: j['photo_count'] ?? 0);
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

class Summary {
  Summary(this.total, this.empty, this.occupied, this.anomaly);
  final int total, empty, occupied, anomaly;
  factory Summary.fromJson(Map<String, dynamic> j) =>
      Summary(j['total'], j['empty'], j['occupied'], j['anomaly']);
}

class DetectionResult {
  DetectionResult({
    required this.model,
    required this.summary,
    required this.statuses,
    required this.cars,
    required this.elapsedMs,
    required this.warning,
  });
  final String model;
  final Summary summary;
  final List<String> statuses; // per slot, urutan sama dengan slot
  final List<Rect> cars;
  final int elapsedMs;
  final String? warning;

  factory DetectionResult.fromJson(Map<String, dynamic> j) => DetectionResult(
        model: j['model'],
        summary: Summary.fromJson(j['summary']),
        statuses: (j['slots'] as List).map((s) => s['status'] as String).toList(),
        cars: (j['cars'] as List).map((c) {
          final b = (c['bbox'] as List).map((v) => (v as num).toDouble()).toList();
          return Rect.fromLTRB(b[0], b[1], b[2], b[3]);
        }).toList(),
        elapsedMs: j['elapsed_ms'] ?? 0,
        warning: j['warning'],
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
