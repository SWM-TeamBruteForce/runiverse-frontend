import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';

/// `RunnerAvatarV2`가 지키는 약속.
///
/// 매칭 완료 카드의 참여자 줄과, 대기 중 카드의 궤도가 같은 것을 쓴다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String nickname,
    String? imageUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: RunnerAvatarV2(nickname: nickname, imageUrl: imageUrl),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('사진이 없으면 첫 글자로 떨어진다', (tester) async {
    await pump(tester, nickname: '러너42');

    expect(find.text('러'), findsOneWidget);
  });

  testWidgets('빈 주소도 사진이 없는 것으로 친다', (tester) async {
    // 서버가 `""`를 주는 경우가 있다. 그대로 넘기면 네트워크 오류가 난다.
    await pump(tester, nickname: '러너42', imageUrl: '');

    expect(find.text('러'), findsOneWidget);
  });

  testWidgets('⚠️ 이름이 비어도 죽지 않는다', (tester) async {
    // 탈퇴한 사람은 이름이 익명 처리돼 오고, 빈 문자열일 수 있다.
    await pump(tester, nickname: '');

    expect(find.text('?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 이름을 읽어 준다', (tester) async {
    // 동그란 사진뿐이라 스크린리더가 읽을 글자가 없다.
    final handle = tester.ensureSemantics();
    await pump(tester, nickname: '러너42');

    expect(find.bySemanticsLabel('러너42'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('동그랗다', (tester) async {
    await pump(tester, nickname: '러너42');

    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration! as BoxDecoration).shape, BoxShape.circle);
  });
}
