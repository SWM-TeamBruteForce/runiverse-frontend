import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 디자인 아이콘 — **이름과 파일이 어긋나지 않는가.**
///
/// 없는 이름으로 그리면 오류 없이 **빈 자리**가 될 뿐이다. 눈으로 찾게 되기
/// 전에 여기서 잡는다.
void main() {
  final dir = Directory('assets/icons');

  List<String> filesOnDisk() =>
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.svg'))
          .map((n) => n.substring(0, n.length - 4))
          .toList()
        ..sort();

  test('⚠️ 모든 이름에 파일이 있다', () {
    // 이름을 더하고 파일을 안 넣는 쪽이 흔하다.
    for (final name in AppIcons.all) {
      expect(
        File(AppIcons.pathOf(name)).existsSync(),
        isTrue,
        reason: '$name 파일이 없다',
      );
    }
  });

  test('⚠️ 파일에 빠진 이름이 없다', () {
    // 반대쪽 — 파일은 넣고 상수를 안 만들면 그 아이콘은 영영 안 쓰인다.
    expect(filesOnDisk(), [...AppIcons.all]..sort());
  });

  test('이름이 전부 snake_case다', () {
    // CLAUDE.md 규칙이기도 하고, 대문자가 섞이면 플랫폼마다 다르게 찾는다.
    for (final name in AppIcons.all) {
      expect(name, matches(RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$')), reason: name);
    }
  });

  test('⚠️ pubspec이 아이콘 폴더를 싣는다', () {
    // 등록을 빠뜨리면 테스트는 다 통과하고 실기기에서만 빈 자리가 된다.
    // yaml 파서를 쓰지 않는다 — 테스트 하나 때문에 의존성을 늘리지 않는다.
    // 주석이 아닌 등록 줄이 있는지만 본다.
    final live = File(
      'pubspec.yaml',
    ).readAsLinesSync().map((l) => l.trim()).where((l) => !l.startsWith('#'));

    expect(live, contains('- assets/icons/'));
  });

  test('중복된 이름이 없다', () {
    expect(AppIcons.all.toSet(), hasLength(AppIcons.all.length));
  });
}
