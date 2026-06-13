import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/db_helper.dart';

final dbHelperProvider = Provider<DbHelper>((ref) {
  return DbHelper();
});
