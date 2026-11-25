import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/city.dart';

/// Sample data. Replace with a repository / API call later.
final citiesProvider = Provider<List<City>>((ref) => const [
      City(
        id: 'mumbai',
        name: 'Mumbai',
        country: 'India',
        description: 'The financial capital of India, on the Arabian Sea.',
      ),
      City(
        id: 'pune',
        name: 'Pune',
        country: 'India',
        description: 'A vibrant hub of education, IT and culture.',
      ),
      City(
        id: 'london',
        name: 'London',
        country: 'United Kingdom',
        description: 'A global city on the River Thames.',
      ),
      City(
        id: 'tokyo',
        name: 'Tokyo',
        country: 'Japan',
        description: 'Neon-lit skyscrapers meet historic temples.',
      ),
    ]);

final cityByIdProvider = Provider.family<City?, String>((ref, id) {
  final cities = ref.watch(citiesProvider);
  for (final city in cities) {
    if (city.id == id) return city;
  }
  return null;
});
