import 'package:bf_stickytask/app/history_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mốc "bây giờ" cố định để test không phụ thuộc lúc chạy: 12h trưa 15/03/2026.
final _now = DateTime(2026, 3, 15, 12);

/// Giờ địa phương → UTC, đúng cách note lưu `doneAt`.
DateTime _local(int year, int month, int day, [int hour = 12]) =>
    DateTime(year, month, day, hour).toUtc();

void main() {
  group('HistoryFilter', () {
    test('Tất cả thì nhận mọi mốc, kể cả note chưa có doneAt', () {
      const filter = HistoryFilter.all;
      expect(filter.isActive, isFalse);
      expect(filter.matches(_local(2020, 1, 1), now: _now), isTrue);
      expect(filter.matches(null, now: _now), isTrue);
    });

    test('Hôm nay tính theo lịch địa phương, trọn ngày', () {
      const filter = HistoryFilter.preset(HistoryRange.today);
      expect(filter.matches(_local(2026, 3, 15, 0), now: _now), isTrue);
      expect(filter.matches(_local(2026, 3, 15, 23), now: _now), isTrue);
      expect(filter.matches(_local(2026, 3, 14, 23), now: _now), isFalse);
      expect(filter.matches(_local(2026, 3, 16, 0), now: _now), isFalse);
    });

    test('7 ngày tính cả hôm nay nên lùi tới ngày 9', () {
      const filter = HistoryFilter.preset(HistoryRange.last7Days);
      expect(filter.matches(_local(2026, 3, 9, 0), now: _now), isTrue);
      expect(filter.matches(_local(2026, 3, 8, 23), now: _now), isFalse);
      expect(filter.matches(_local(2026, 3, 15, 23), now: _now), isTrue);
    });

    test('30 ngày lùi tới ngày 14/02', () {
      const filter = HistoryFilter.preset(HistoryRange.last30Days);
      expect(filter.matches(_local(2026, 2, 14, 0), now: _now), isTrue);
      expect(filter.matches(_local(2026, 2, 13, 23), now: _now), isFalse);
    });

    test('khoảng tự chọn tính trọn cả ngày đầu lẫn ngày cuối', () {
      final filter = HistoryFilter.custom(
        DateTimeRange(start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 4)),
      );
      expect(filter.matches(_local(2026, 3, 2, 0), now: _now), isTrue);
      // Ngày cuối phải tính hết 23h59, không cắt ở 0h.
      expect(filter.matches(_local(2026, 3, 4, 23), now: _now), isTrue);
      expect(filter.matches(_local(2026, 3, 1, 23), now: _now), isFalse);
      expect(filter.matches(_local(2026, 3, 5, 0), now: _now), isFalse);
    });

    test('note chưa có doneAt không lọt vào khoảng nào', () {
      const filter = HistoryFilter.preset(HistoryRange.today);
      expect(filter.matches(null, now: _now), isFalse);
    });

    test('nhãn chip: preset lấy tên, khoảng tự chọn hiện ngày', () {
      expect(const HistoryFilter.preset(HistoryRange.last7Days).label, '7 ngày');
      expect(
        HistoryFilter.custom(
          DateTimeRange(start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 4)),
        ).label,
        '02/03 – 04/03',
      );
      // Chọn đúng một ngày thì đừng hiện "02/03 – 02/03".
      expect(
        HistoryFilter.custom(
          DateTimeRange(start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 2)),
        ).label,
        '02/03',
      );
    });
  });
}
