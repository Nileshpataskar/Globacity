import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/city_providers.dart';
import '../../widgets/city_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Globacity')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: cities.length,
        itemBuilder: (context, index) {
          final city = cities[index];
          return CityCard(
            city: city,
            onTap: () => context.goNamed(
              'details',
              pathParameters: {'id': city.id},
            ),
          );
        },
      ),
    );
  }
}
