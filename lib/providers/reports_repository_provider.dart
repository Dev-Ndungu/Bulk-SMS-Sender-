library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (_) => ReportsRepository(),
);