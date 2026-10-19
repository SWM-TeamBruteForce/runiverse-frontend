/// 화면이 **바닥을 시스템에 양보했는가.**
///
/// ## 왜 필요한가
///
/// 안드로이드는 화면 맨 아래를 제스처 바(24dp 안팎)나 3버튼 내비게이션
/// 바(48dp 안팎)가 덮는다. 앱은 그만큼 비켜야 하는데 **비키는 방법이 화면마다
/// 다르다** — `SafeArea`로 감싸거나, 바닥 여백에 `MediaQuery`의 하단 값을
/// 직접 더하거나.
///
/// 섞여 있는 것 자체는 괜찮다. 시안이 사진을 상태바 뒤까지 까는 화면은
/// `SafeArea`로 감쌀 수 없어서 직접 더해야 한다. 문제는 **어느 쪽도 하지 않은
/// 화면이 눈에 띄지 않는다**는 것이다. 로그인 화면이 그렇게 들어왔다 —
/// 주석에는 "아래쪽 여백만 아래에서 따로 준다"고 적혀 있었는데 고정값만
/// 있었고, 가입 링크가 제스처 바에 깔렸다.
///
/// `test/v2_screen_background_test.dart`가 **바탕색**을 보는 것과 짝이다.
/// 그쪽은 "자기 배경을 깔았는가", 이쪽은 "자기 바닥을 비켰는가"를 본다.
///
/// ## 판정 방법
///
/// 소스를 읽는다. 위젯을 띄워 재는 쪽이 정확하지만 화면마다 provider 를
/// 세우는 값이 이 한 줄을 지키는 값보다 크다. **빠뜨림을 잡는 것이 목적**이고
/// 빠뜨림은 소스에 드러난다. 실제로 가려지는지는 그 화면의 위젯 테스트가
/// 여백을 바꿔 가며 본다(`sign_in_page_test.dart`의 `맨 아래 줄`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 바닥을 책임지는 표식.
///
/// ⚠️ **`SafeArea`가 있어도 `bottom: false`면 책임지지 않은 것이다.** 위만
/// 받고 아래는 직접 주겠다는 뜻이라, 직접 주는 쪽도 함께 있어야 한다.
bool handlesBottomInset(String source) {
  // 시스템 하단 여백을 직접 읽는다. 어떻게 쓰든 읽었다는 것은 의식했다는 뜻이다.
  const reads = [
    'paddingOf(context).bottom',
    'padding.bottom',
    'viewPaddingOf(context).bottom',
  ];
  if (reads.any(source.contains)) return true;

  // Scaffold 가 알아서 깔아 주는 자리.
  if (source.contains('bottomNavigationBar:')) return true;

  // SafeArea 하나로 끝낸 경우. 아래를 끈 것이 하나라도 있으면 통하지 않는다.
  return source.contains('SafeArea(') && !source.contains('bottom: false');
}

/// 검사에서 빼는 화면과 그 이유.
///
/// ⚠️ **"지금 안 깨지니까"는 이유가 아니다.** 바닥에 닿는 것이 구조적으로
/// 없어야 한다. 줄이 하나라도 붙는 순간 목록에서 빼고 여백을 받아야 한다.
const exempt = <String, String>{
  'lib/features/onboarding/presentation/splash_page.dart':
      '워드마크와 태그라인이 화면 정중앙에 있고 바닥에 닿는 것이 없다. '
      '사진처럼 꽉 채우는 배경만 아래까지 간다.',
  'lib/features/record/presentation/record_detail_page.dart':
      '이 Scaffold 는 불러오는 중·실패일 때만 쓴다. 본문이 `Center` 하나라 '
      '바닥에 닿지 않는다. 기록 본문은 `RunResultView` 가 따로 그린다.',
  'lib/dev/token_preview.dart': '토큰을 눈으로 보는 개발용 화면. 앱 경로에 없다.',
};

void main() {
  group('판정', () {
    test('SafeArea 로 감싸면 통과한다', () {
      expect(
        handlesBottomInset("Scaffold(body: SafeArea(child: Text('hi')))"),
        isTrue,
      );
    });

    test('⚠️ 아래를 끈 SafeArea 만으로는 통과하지 못한다', () {
      expect(
        handlesBottomInset(
          "Scaffold(body: SafeArea(bottom: false, child: Text('hi')))",
        ),
        isFalse,
      );
    });

    test('아래를 껐어도 직접 더하면 통과한다', () {
      expect(
        handlesBottomInset('''
Scaffold(
  body: SafeArea(
    bottom: false,
    child: Padding(
      padding: EdgeInsets.only(
        bottom: AppSpacing.space6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Text('hi'),
    ),
  ),
)
'''),
        isTrue,
      );
    });

    test('탭 바를 단 화면은 Scaffold 가 깔아 준다', () {
      expect(
        handlesBottomInset(
          "Scaffold(body: Text('hi'), bottomNavigationBar: Bar())",
        ),
        isTrue,
      );
    });

    test('⚠️ 둘 다 없으면 잡는다', () {
      expect(
        handlesBottomInset(
          "Scaffold(body: SingleChildScrollView(child: Text('hi')))",
        ),
        isFalse,
      );
    });
  });

  test('⚠️ 면제 목록이 실재하는 화면만 가리킨다', () {
    // 파일을 옮기거나 지우면 목록이 조용히 낡는다. 그러면 **새로 들어온
    // 화면이 그 경로를 쓸 때 공짜로 면제된다.**
    for (final path in exempt.keys) {
      expect(File(path).existsSync(), isTrue, reason: '$path 가 없다');
    }
  });

  test('⚠️ 모든 화면이 자기 바닥을 비킨다', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      if (exempt.containsKey(path)) continue;

      final source = entity.readAsStringSync();
      if (!source.contains('Scaffold(')) continue;
      if (handlesBottomInset(source)) continue;

      offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '화면 맨 아래는 제스처 바나 3버튼 내비게이션 바가 덮는다. '
          '`SafeArea` 로 감싸거나, 위를 상태바 뒤까지 깔아야 해서 감쌀 수 '
          '없다면 바닥 여백에 `MediaQuery.paddingOf(context).bottom` 을 '
          '더한다. 바닥에 닿는 것이 구조적으로 없는 화면이라면 이 파일의 '
          '`exempt` 에 이유와 함께 적는다.',
    );
  });
}
