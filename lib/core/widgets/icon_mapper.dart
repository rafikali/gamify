import 'package:flutter/material.dart';

IconData categoryIcon(String iconName) {
  switch (iconName) {
    case 'nutrition':
      return Icons.local_pizza_outlined;
    case 'spa':
      return Icons.eco_outlined;
    case 'work':
      return Icons.work_outline;
    case 'pets':
      return Icons.pets_outlined;
    case 'lightbulb':
      return Icons.lightbulb_outline;
    case 'directions_car':
      return Icons.directions_car_filled_outlined;
    default:
      return Icons.school_outlined;
  }
}

Color parseHexColor(String hex) {
  final normalized = hex.replaceAll('#', '');
  final buffer = StringBuffer();
  if (normalized.length == 6) {
    buffer.write('ff');
  }
  buffer.write(normalized);
  return Color(int.parse(buffer.toString(), radix: 16));
}
