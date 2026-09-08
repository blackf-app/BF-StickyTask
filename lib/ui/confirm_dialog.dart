import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Popup xác nhận cho thao tác xoá. Trả `true` khi user đồng ý, `false` khi
/// bấm Thôi **hoặc** bấm ra ngoài / Esc — nên chỗ gọi chỉ cần `if (ok)`.
///
/// Mọi thao tác xoá trong app đi qua đây để chữ nghĩa và màu nút giống nhau;
/// đừng tự dựng AlertDialog riêng ở chỗ khác nữa.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,

  /// Nội dung dòng note đang bị xoá — hiện lại để user thấy đúng dòng mình bấm.
  String? detail,
  String confirmLabel = 'Xoá',
  String cancelLabel = 'Thôi',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      final paper = context.paper;
      return AlertDialog(
        backgroundColor: paper.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kPaperRadius),
        ),
        insetPadding: const EdgeInsets.all(12),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(fontSize: 12.5, color: paper.inkSoft),
              ),
              if (detail != null && detail.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: paper.line.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail.trim(),
                    // Note dài thì cắt bớt, đừng để dialog cao quá màn hình.
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: paper.ink),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: paper.danger),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
