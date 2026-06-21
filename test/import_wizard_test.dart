import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/ui/screens/import/import_wizard_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CSV / Excel Import Wizard Screen Tests', () {
    late DbHelper dbHelper;

    setUp(() async {
      dbHelper = DbHelper();
      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      final path = '$databasePath/godown_management.db';
      await deleteDatabase(path);
    });

    testWidgets('Import Wizard Renders Screen and select type correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ImportWizardScreen(),
          ),
        ),
      );

      // Verify header steps and title
      expect(find.text('Excel / CSV Import Wizard'), findsOneWidget);
      expect(find.text('Step 1: Choose Import Type'), findsOneWidget);
      
      // Default type is Parties, check if Parties card is active
      expect(find.text('Parties'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);

      // Switch selection to Products
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      // Verify guide changed to products (HSN Code is required for products)
      expect(find.text('HSN Code'), findsOneWidget);
    });

    testWidgets('Wizard Next step requires file attachment', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ImportWizardScreen(),
          ),
        ),
      );

      // Tap Next: Select File
      await tester.tap(find.text('Next: Select File'));
      await tester.pumpAndSettle();

      expect(find.text('Step 2: Upload CSV or Excel file'), findsOneWidget);
      expect(find.text('Tap to Browse File'), findsOneWidget);

      // Confirm Next button is disabled since no file is uploaded
      final nextButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Next: Map Columns'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(nextButton.onPressed, isNull);
    });
  });
}
