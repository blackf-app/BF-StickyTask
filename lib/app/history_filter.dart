import 'package:flutter/material.dart';

/// Các khoảng thời gian lọc sẵn cho tab History.
enum HistoryRange {
  all('Tất cả'),
  today('Hôm nay'),
  last7Days('7 ngày'),
  last30Days('30 ngày'),
  custom('Khoảng ngày');

  const HistoryRange(this.label);

  final String label;
}

/// Bộ lọc theo ngày của tab History: một khoảng chọn sẵn, hoặc khoảng ngày do
/// user tự chọn.
///
/// Mốc so sánh là **giờ địa phương**: note lưu `doneAt` ở UTC, còn "hôm nay"
/// thì phải theo lịch của máy đang xem, không thì 7 giờ sáng ở VN lại đang là
/// hôm qua theo UTC.
@immutable
class HistoryFilter {
  const HistoryFilter._(this.range, this.customRange);

  const HistoryFilter.preset(HistoryRange range) : this._(range, null);

  /// Khoảng tự chọn. [DateTimeRange.start] và `.end` là ngày (giờ bị bỏ qua),
  /// cả hai đầu đều **được tính vào** khoảng lọc.
  const HistoryFilter.custom(DateTimeRange range)
      : this._(HistoryRange.custom, range);

  static const HistoryFilter all = HistoryFilter.preset(HistoryRange.all);

  final HistoryRange range;
  final DateTimeRange? customRange;

  bool get isActive => range != HistoryRange.all;

  /// Nhãn ngắn cho chip đang chọn: khoảng tự chọn thì hiện luôn ngày.
  String get label {
    final custom = customRange;
    if (range != HistoryRange.custom || custom == null) return range.label;
    final from = _dayMonth(custom.start);
    final to = _dayMonth(custom.end);
    return from == to ? from : '$from – $to';
  }

  /// Nửa khoảng `[từ, đến)` theo giờ địa phương, null khi không lọc gì.
  /// Đầu `đến` là 0h ngày kế tiếp để ngày cuối được tính trọn vẹn.
  ({DateTime from, DateTime to})? boundsAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (range) {
      HistoryRange.all => null,
      HistoryRange.today => (from: today, to: tomorrow),
      // "7 ngày" tính cả hôm nay, nên lùi 6 ngày.
      HistoryRange.last7Days => (
          from: today.subtract(const Duration(days: 6)),
          to: tomorrow
        ),
      HistoryRange.last30Days => (
          from: today.subtract(const Duration(days: 29)),
          to: tomorrow
        ),
      HistoryRange.custom => switch (customRange) {
          null => null,
          final r => (
              from: DateTime(r.start.year, r.start.month, r.start.day),
              to: DateTime(r.end.year, r.end.month, r.end.day)
                  .add(const Duration(days: 1)),
            ),
        },
    };
  }

  /// [time] là mốc UTC lưu trong note; null (chưa có `doneAt`) thì không khớp
  /// khoảng nào — trừ khi đang không lọc.
  bool matches(DateTime? time, {DateTime? now}) {
    final bounds = boundsAt(now ?? DateTime.now());
    if (bounds == null) return true;
    if (time == null) return false;
    final local = time.toLocal();
    return !local.isBefore(bounds.from) && local.isBefore(bounds.to);
  }

  static String _dayMonth(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.range == range &&
      other.customRange?.start == customRange?.start &&
      other.customRange?.end == customRange?.end;

  @override
  int get hashCode => Object.hash(range, customRange?.start, customRange?.end);
}
