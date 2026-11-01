import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:parking_ui/api.dart';
import 'package:parking_ui/main.dart';

void main() {
  test('Photo.fromJson membaca slot dan hasil deteksi', () {
    final photo = Photo.fromJson({
      'id': 'abc',
      'original_name': 'cropgedq.jpg',
      'width': 960,
      'height': 318,
      'slots': [
        {
          'id': 1,
          'label': 'Slot A1',
          'bbox': [97, 120, 189, 166],
        },
      ],
      'last_result': {
        'model': 'best_3.pt',
        'summary': {'total': 1, 'empty': 0, 'occupied': 1, 'anomaly': 0},
        'slots': [
          {
            'id': 1,
            'label': 'Slot A1',
            'bbox': [97, 120, 189, 166],
            'status': 'occupied',
            'cars': 1,
          },
        ],
        'cars': [
          {
            'bbox': [90.5, 100, 200, 170],
            'conf': 0.8,
          },
        ],
        'elapsed_ms': 50,
        'warning': null,
        'layout_source': 'photo',
        'layout_warning': null,
      },
    });
    expect(photo.slots.single.rect, const Rect.fromLTRB(97, 120, 189, 166));
    expect(photo.lastResult!.statuses, ['occupied']);
    expect(photo.lastResult!.slots.single.label, 'Slot A1');
    expect(photo.lastResult!.cars.single.left, 90.5);
    expect(photo.slots.single.toJson()['bbox'], [97, 120, 189, 166]);
  });

  test('Building.code mengambil kode setelah kata "Gedung"', () {
    Building b(String name) =>
        Building.fromJson({'id': 'x', 'name': name, 'photo_count': 0, 'lot_count': 0, 'layout_photo_id': null});
    expect(b('Gedung T').code, 'T');
    expect(b('gedung  ab').code, 'AB');
    expect(b('Perpustakaan').code, 'P');
    expect(b('Gedung Baru').code, 'BAR');
    expect(b('Gedung Q').location, '');
  });

  testWidgets('Beranda menampilkan judul dan langkah dalam bahasa Indonesia', (tester) async {
    await tester.pumpWidget(const ParkingApp());
    expect(find.text('Mau cek parkiran di mana?'), findsOneWidget);
    expect(find.text('Pilih gedung'), findsOneWidget);
    expect(find.text('Unggah foto'), findsOneWidget);
    expect(find.text('Hasil deteksi'), findsOneWidget);
    expect(find.text('PetraPark'), findsOneWidget);
  });
}
