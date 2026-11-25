import 'package:flutter/material.dart';

import '../models/city.dart';

class CityCard extends StatelessWidget {
  const CityCard({super.key, required this.city, this.onTap});

  final City city;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Text(
            city.name[0],
            style: TextStyle(color: colors.onPrimaryContainer),
          ),
        ),
        title: Text(city.name),
        subtitle: Text(city.country),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
