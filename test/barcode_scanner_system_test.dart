import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';
import 'package:joyce_pos_flutter/core/theme/app_theme.dart';
import 'package:joyce_pos_flutter/core/utils/barcode_scanner_service.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/ui/screens/pos_screen.dart';
import 'package:joyce_pos_flutter/ui/screens/products_screen.dart';
import 'package:joyce_pos_flutter/ui/widgets/joyce_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BarcodeScannerService unit tests', () {
    tearDown(() {
      BarcodeScannerService.instance.dispose();
    });

    test('dispatch routes to latest subscriber (modal priority)', () {
      final logA = <String>[];
      final logB = <String>[];

      final unsubA = BarcodeScannerService.instance.subscribe((bc) => logA.add(bc));
      BarcodeScannerService.instance.dispatch('4800016644401');

      expect(logA, equals(['4800016644401']));
      expect(logB, isEmpty);

      // Add Modal subscriber on top
      final unsubB = BarcodeScannerService.instance.subscribe((bc) => logB.add(bc));
      BarcodeScannerService.instance.dispatch('4800016644402');

      // Modal B receives, background A does not
      expect(logA, equals(['4800016644401']));
      expect(logB, equals(['4800016644402']));

      // Modal B closes
      unsubB();
      BarcodeScannerService.instance.dispatch('4800016644403');

      // Now A receives again
      expect(logA, equals(['4800016644401', '4800016644403']));
      unsubA();
    });
  });

  group('Barcode scanning in POS and Products UI', () {
    late Directory tempDir;
    late DatabaseService dbService;
    late PosRepository repo;
    late AppState appState;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('joyce_barcode_ui_');
      dbService = DatabaseService();
      final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
      repo = PosRepository(dbService: dbService, branchManager: branchMgr);
      repo.saveProduct({
        'name': 'Lucky Me Canton Calamansi',
        'barcode': '4800016644403',
        'category': 'Noodles',
        'price': 20.0,
        'cost': 15.0,
        'stock': 15,
      });
      repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);
      appState = AppState(repo: repo);
      appState.loginWithPin('0000');
    });

    tearDown(() {
      BarcodeScannerService.instance.dispose();
      dbService.close();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('PosScreen adds product to cart when barcode is scanned', (tester) async {
      tester.view.physicalSize = const Size(1366, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: PosScreen(appState: appState)),
        ),
      );
      await tester.pump();

      expect(find.text('Lucky Me Canton Calamansi'), findsOneWidget);
      expect(find.text('15 in stock'), findsOneWidget);

      // Simulate hardware barcode scan
      BarcodeScannerService.instance.dispatch('4800016644403');
      await tester.pump();

      // Product was added to cart, remaining stock is now 14
      expect(find.text('14 in stock'), findsOneWidget);
      expect(find.text('Added "Lucky Me Canton Calamansi" to cart (₱20.00)'), findsOneWidget);

      // Let first snackbar animate away completely
      await tester.pumpAndSettle();

      // Unknown barcode scan
      BarcodeScannerService.instance.dispatch('9999999999999');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      final content = snackBar.content as Text;
      expect(content.data, contains('9999999999999'));
    });

    testWidgets('ProductsScreen search populates on barcode scan and modal receives barcode', (tester) async {
      tester.view.physicalSize = const Size(1366, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: ProductsScreen(appState: appState)),
        ),
      );
      await tester.pump();

      // Scan barcode in Products screen
      BarcodeScannerService.instance.dispatch('4800016644403');
      await tester.pump();

      // Search field is populated
      final searchField = tester.widget<TextField>(find.byType(TextField).first);
      expect(searchField.controller?.text, equals('4800016644403'));

      // Open Add Product modal
      await tester.tap(find.widgetWithText(JoyceButton, 'Add Product'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      // Scan new barcode into Add Product modal
      BarcodeScannerService.instance.dispatch('748100234567');
      await tester.pump();

      // Verify the barcode textfield in the modal has the scanned barcode
      expect(find.text('748100234567'), findsOneWidget);
    });
  });
}
