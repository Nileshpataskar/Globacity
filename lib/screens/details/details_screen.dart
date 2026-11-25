import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/city_providers.dart';

class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.cityId});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(cityByIdProvider(cityId));
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(city?.name ?? 'Not found')),
      body: city == null
          ? const Center(child: Text('City not found'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(city.name, style: textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(city.country, style: textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Text(city.description, style: textTheme.bodyLarge),
                ],
              ),
            ),
    );
  }
}
