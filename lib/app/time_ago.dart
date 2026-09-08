/// Mô tả thời gian kiểu "5 phút trước" cho tab History.
String timeAgoVi(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final diff = DateTime.now().difference(local);

  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays == 1) return 'hôm qua';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';

  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final sameYear = local.year == DateTime.now().year;
  return sameYear ? '$d/$m' : '$d/$m/${local.year}';
}
