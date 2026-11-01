import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../theme.dart';

/// Kerangka halaman pengunjung: header PetraPark, isi di tengah, footer.
class PetraShell extends StatelessWidget {
  const PetraShell({super.key, required this.child, this.step, this.onManage});

  final Widget child;
  final int? step; // 1..3, ditampilkan sebagai stepper di atas isi
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 760;
          final hPad = narrow ? 16.0 : 48.0;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      _Header(hPad: hPad, onManage: onManage),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1184),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (step != null) ...[
                                  StepIndicator(step: step!, compact: narrow),
                                  const SizedBox(height: 32),
                                ],
                                child,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Footer(hPad: hPad, narrow: narrow),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hPad, this.onManage});
  final double hPad;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Pk.line)),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 14),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1184 - 96),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Pk.dark, borderRadius: BorderRadius.circular(3)),
              child: const Text(
                'P',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PetraPark', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.1)),
                Text('SMART PARKING', style: TextStyle(color: Pk.muted, fontSize: 9, letterSpacing: 1.6)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<bool?>(
                valueListenable: serverOnline,
                builder: (context, online, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(width: 7, height: 7, color: online == false ? Pk.error : Pk.ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        online == false ? 'Sistem tidak terhubung' : 'Sistem aktif',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: online == false ? Pk.error : Pk.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onManage != null) ...[
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Kelola', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.hPad, required this.narrow});
  final double hPad;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: Pk.muted);
    const left = Text('PetraPark · Deteksi ketersediaan parkir UK Petra', style: style);
    const right = Text('Berdasarkan foto yang diunggah, bukan data langsung', style: style);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Pk.line)),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
      alignment: Alignment.center,
      child: SizedBox(
        width: 1184 - 96,
        child: Wrap(
          alignment: narrow ? WrapAlignment.start : WrapAlignment.spaceBetween,
          spacing: 24,
          runSpacing: 4,
          children: const [left, right],
        ),
      ),
    );
  }
}

/// 1 Pilih gedung — 2 Unggah foto — 3 Hasil deteksi
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.step, this.compact = false});
  final int step;
  final bool compact;

  static const _labels = ['Pilih gedung', 'Unggah foto', 'Hasil deteksi'];

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final active = i + 1 == step;
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Pk.dark : Pk.fill,
                border: Border.all(color: active ? Pk.dark : Pk.line),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? Colors.white : Pk.muted),
              ),
            ),
            if (!compact || active) ...[
              const SizedBox(width: 8),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? Pk.ink : Pk.muted,
                ),
              ),
            ],
          ],
        ),
      );
      if (i < _labels.length - 1) {
        items.add(
          Container(
            width: compact ? 20 : 56,
            height: 1,
            color: Pk.line,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
        );
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

/// Kotak huruf gedung, mis. "T".
class BuildingTile extends StatelessWidget {
  const BuildingTile({super.key, required this.code, this.size = 48});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Pk.fill,
        border: Border.all(color: Pk.line),
      ),
      child: Text(
        code,
        maxLines: 1,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * (code.length > 1 ? 0.3 : 0.42)),
      ),
    );
  }
}

/// Bar gedung terpilih dengan tautan "Ganti gedung".
class SelectedBuildingBar extends StatelessWidget {
  const SelectedBuildingBar({super.key, required this.building, required this.onChange});
  final Building building;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final where = building.location.isEmpty ? 'Gedung terpilih' : '${building.location} · Gedung terpilih';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: Pk.line),
      ),
      child: Row(
        children: [
          BuildingTile(code: building.code, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(building.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(where, style: const TextStyle(fontSize: 11, color: Pk.muted)),
              ],
            ),
          ),
          LinkText('Ganti gedung', onTap: onChange),
        ],
      ),
    );
  }
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
      ),
    );
  }
}

/// Judul halaman + kalimat penjelas.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle, this.center = false});
  final String title;
  final String subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: align,
          style: TextStyle(
            fontSize: (center ? 36 : 28) * (narrow ? 0.75 : 1),
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: align,
          style: const TextStyle(fontSize: 14, color: Pk.muted),
        ),
      ],
    );
  }
}

/// Label kecil berhuruf kapital, mis. "DETEKSI LOT PARKIR".
class TagLabel extends StatelessWidget {
  const TagLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Pk.fill,
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Pk.muted),
      ),
    );
  }
}

/// Kotak berbingkai tipis yang dipakai untuk panel-panel di halaman.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Pk.page,
        border: Border.all(color: Pk.line),
      ),
      child: child,
    );
  }
}

/// Panel samping "Agar lot mudah terdeteksi".
class TipsPanel extends StatelessWidget {
  const TipsPanel({super.key, required this.buildingName});
  final String buildingName;

  @override
  Widget build(BuildContext context) {
    final tips = [
      'Ambil foto area parkir $buildingName.',
      'Pastikan garis lot dan kendaraan terlihat jelas.',
      'Gunakan foto terang, tidak buram, dan tidak terhalang.',
    ];
    return Panel(
      color: const Color(0xFFFAFAFA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agar lot mudah terdeteksi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          for (var i = 0; i < tips.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(tips[i], style: const TextStyle(fontSize: 12, color: Pk.muted, height: 1.4)),
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          const Text('Format yang didukung: JPG, PNG, WEBP.', style: TextStyle(fontSize: 11, color: Pk.muted)),
        ],
      ),
    );
  }
}

/// Dua kolom (isi utama + panel samping) di layar lebar, bertumpuk di layar sempit.
class TwoColumn extends StatelessWidget {
  const TwoColumn({super.key, required this.main, required this.side, this.sideWidth = 280});
  final Widget main;
  final Widget side;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 20), side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 20),
            SizedBox(width: sideWidth, child: side),
          ],
        );
      },
    );
  }
}
