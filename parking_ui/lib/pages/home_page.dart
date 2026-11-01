import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../theme.dart';
import '../widgets/petra.dart';
import 'building_list_page.dart';
import 'detect_flow_page.dart';

/// Langkah 1: pengunjung memilih gedung parkir.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  Future<void> _open(Building b) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetectFlowPage(building: b)));
    _load();
  }

  Future<void> _manage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BuildingListPage()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final buildings = _buildings;
    return PetraShell(
      step: 1,
      onManage: _manage,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TagLabel('DETEKSI LOT PARKIR'),
          const SizedBox(height: 18),
          const PageHeading(
            title: 'Mau cek parkiran di mana?',
            subtitle: 'Pilih gedung parkir, lalu unggah foto untuk membantu mendeteksi ketersediaan lot parkir.',
            center: true,
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: _error != null
                ? ErrorView(message: '$_error\n\nPastikan backend sudah berjalan.', onRetry: _load)
                : buildings == null
                ? const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
                : buildings.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Belum ada gedung. Tambahkan gedung melalui menu Kelola.',
                      style: TextStyle(color: Pk.muted),
                    ),
                  )
                : _grid(buildings),
          ),
          const SizedBox(height: 28),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 6, height: 6, child: ColoredBox(color: Pk.ink)),
              SizedBox(width: 8),
              Text('Mendukung format JPG, PNG, dan WEBP', style: TextStyle(fontSize: 12, color: Pk.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grid(List<Building> buildings) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 16.0;
        final columns = c.maxWidth >= 600 ? 2 : 1;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in buildings)
              SizedBox(
                width: width,
                child: _BuildingCard(building: b, onTap: () => _open(b)),
              ),
          ],
        );
      },
    );
  }
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({required this.building, required this.onTap});
  final Building building;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (building.location.isNotEmpty) building.location,
      if (building.lotCount == 0) 'lot belum diatur',
    ].join(' · ');
    return Material(
      color: Pk.page,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(border: Border.all(color: Pk.line)),
          child: Row(
            children: [
              BuildingTile(code: building.code),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(details, style: const TextStyle(fontSize: 12, color: Pk.muted)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, size: 18, color: Pk.ink),
            ],
          ),
        ),
      ),
    );
  }
}
