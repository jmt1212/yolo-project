import 'package:flutter/material.dart';

import 'pages/building_list_page.dart';

void main() => runApp(const ParkingApp());

class ParkingApp extends StatelessWidget {
  const ParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deteksi Lot Parkir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B6EF0), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF3B6EF0), brightness: Brightness.dark, useMaterial3: true),
      home: const BuildingListPage(),
    );
  }
}
