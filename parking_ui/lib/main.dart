import 'package:flutter/material.dart';

import 'common.dart';
import 'pages/home_page.dart';
import 'theme.dart';

void main() {
  startHealthChecks();
  runApp(const ParkingApp());
}

class ParkingApp extends StatelessWidget {
  const ParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetraPark · Deteksi Lot Parkir',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}
