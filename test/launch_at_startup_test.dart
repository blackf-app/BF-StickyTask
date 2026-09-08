import 'dart:io';

import 'package:bf_stickytask/app/launch_at_startup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channel chỉ có phía macOS (Windows đi thẳng registry bằng Dart), nên nhóm
/// test này chỉ chạy trên macOS.
final _skipReason = Platform.isMacOS
    ? null
    : 'Channel mở-khi-khởi-động chỉ có trên macOS';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(LaunchAtStartup.channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    messenger.setMockMethodCallHandler(LaunchAtStartup.channel, null);
  });

  group('LaunchAtStartup', () {
    test('đọc trạng thái từ native lúc load', () async {
      mockChannel((_) async => {
            'supported': true,
            'enabled': true,
            'requiresApproval': false,
          });

      await LaunchAtStartup.instance.load();

      expect(calls.single.method, 'status');
      expect(LaunchAtStartup.instance.supported, isTrue);
      expect(LaunchAtStartup.instance.enabled, isTrue);
    });

    test('macOS cũ báo không hỗ trợ thì setEnabled không gọi native',
        () async {
      mockChannel((_) async => {'supported': false, 'enabled': false});

      await LaunchAtStartup.instance.load();
      await LaunchAtStartup.instance.setEnabled(true);

      expect(LaunchAtStartup.instance.supported, isFalse);
      expect(calls.map((c) => c.method), ['status']);
    });

    test('bật thì gửi setEnabled + nhận lại trạng thái mới', () async {
      var enabled = false;
      mockChannel((call) async {
        if (call.method == 'setEnabled') {
          enabled = (call.arguments as Map)['enabled'] as bool;
        }
        return {
          'supported': true,
          'enabled': enabled,
          'requiresApproval': false,
        };
      });

      await LaunchAtStartup.instance.load();
      await LaunchAtStartup.instance.toggle();

      expect(calls.last.method, 'setEnabled');
      expect((calls.last.arguments as Map)['enabled'], isTrue);
      expect(LaunchAtStartup.instance.enabled, isTrue);
    });

    test('macOS còn chờ duyệt vẫn tính là đang bật, có cờ riêng', () async {
      mockChannel((_) async => {
            'supported': true,
            'enabled': true,
            'requiresApproval': true,
          });

      await LaunchAtStartup.instance.load();

      expect(LaunchAtStartup.instance.enabled, isTrue);
      expect(LaunchAtStartup.instance.state.requiresApproval, isTrue);
    });

    test('native báo lỗi thì giữ trạng thái cũ và nhớ lỗi', () async {
      mockChannel((call) async {
        if (call.method == 'setEnabled') {
          throw PlatformException(code: 'smAppService', message: 'không được');
        }
        return {'supported': true, 'enabled': false, 'requiresApproval': false};
      });

      await LaunchAtStartup.instance.load();
      await LaunchAtStartup.instance.setEnabled(true);

      expect(LaunchAtStartup.instance.enabled, isFalse);
      expect(LaunchAtStartup.instance.state.error, 'không được');
    });

    test('không có native (chưa đăng ký channel) thì coi như không hỗ trợ',
        () async {
      messenger.setMockMethodCallHandler(LaunchAtStartup.channel, null);

      await LaunchAtStartup.instance.load();

      expect(LaunchAtStartup.instance.supported, isFalse);
    });
  }, skip: _skipReason);
}
