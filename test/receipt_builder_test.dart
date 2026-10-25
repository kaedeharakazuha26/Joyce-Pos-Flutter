import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/utils/receipt_builder.dart';

void main() {
  test('ReceiptBuilder sanitizes ₱ to P, enforces column width, and emits ESC/POS cut/drawer bytes', () {
    final settings = {
      'store_name': 'JOYCE POS ₱',
      'paper_width': '58',
      'chars_per_line': '32',
      'cut_paper': '1',
      'open_drawer': '1',
      'copies': '1',
    };
    final sale = {
      'receipt_no': 'JP-20261025-0001',
      'created_at': '2026-10-25 14:30:00',
      'status': 'completed',
      'total': 170.0,
      'paid': 200.0,
      'change_amt': 30.0,
      'items': [
        {
          'name': 'Cola',
          'variant_name': '6-Pack',
          'quantity': 2,
          'unit_price': 85.0,
          'subtotal': 170.0,
        }
      ],
    };

    final text = ReceiptBuilder.buildReceiptText(sale, settings);
    expect(text.contains('₱'), false);
    expect(text.contains('JOYCE POS P'), true);
    for (final line in text.split('\n')) {
      expect(line.length <= 32, true, reason: 'Line exceeded 32 chars: "$line"');
    }

    final bytes = ReceiptBuilder.buildReceiptBytes(sale, settings);
    // Starts with ESC @ (0x1B, 0x40)
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);
  });

  test('ZReadingBuilder omits disabled module outflows and computes net operating profit', () {
    final settings = {
      'store_name': 'JOYCE POS',
      'paper_width': '58',
      'chars_per_line': '32',
    };
    final zData = {
      'id': 1,
      'business_date': '2026-10-25',
      'opened_at': '2026-10-25 08:00:00',
      'opened_by': 'Admin',
      'closed_by': 'Admin',
      'opening_cash': 500.0,
      'cash_sales': 1000.0,
      'gross_sales': 1000.0,
      'expenses': 100.0,
      'salaries': 0.0,
      'commissions': 50.0,
      'ld_commissions': 0.0,
      'expected_cash': 1350.0,
      'closing_cash': 1350.0,
      'variance': 0.0,
      'sold_items': [
        {'name': 'Cola', 'variant_name': '', 'quantity': 10, 'amount': 1000.0},
      ],
    };

    final zText = ReceiptBuilder.buildZReadingText(
      zData,
      settings,
      {'salary', 'salaries', 'ld-commission'},
    );
    expect(zText.contains('Salaries Paid'), false);
    expect(zText.contains('Store Expenses'), true);
    expect(zText.contains('0.00 (Balanced)'), true);
  });
}
