import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_slide.dart';

/// 작성 화면이 세우는 **사진 한 장**(설계 6-3).
///
/// 화면 상태(어느 장을 보고 있나·고르는 중인가)는 들지 않는다 — 부르는 쪽이
/// 든다. 여기서 보는 것은 **한 장이 혼자 옳게 서는가**다.
void main() {
  const saved = SavedPhoto(id: 'photo-1', url: 'https://example.invalid/a.jpg');

  Future<void> pump(WidgetTester tester, Widget slide) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: slide),
    ),
  );

  Widget photoSlide({
    CardPhotoDraft photo = saved,
    int index = 0,
    int total = 1,
    bool isCover = true,
    VoidCallback? onMakeCover,
    VoidCallback? onRemove,
  }) => CardPhotoSlide(
    photo: photo,
    index: index,
    total: total,
    isCover: isCover,
    onAlign: ({alignX, alignY}) {},
    onCaption: (_) {},
    onMakeCover: onMakeCover ?? () {},
    onRemove: onRemove ?? () {},
  );

  testWidgets('첫 장이면 넣지 않아도 된다고 말한다', (tester) async {
    await pump(tester, CardAddPhotoSlide(first: true, onPick: () {}));

    expect(find.text(AppStrings.recordCardPhotoEmpty), findsOneWidget);
  });

  testWidgets('⚠️ 둘째 장부터는 그 말을 하지 않는다', (tester) async {
    // 사진을 이미 한 장 넣은 사람에게 "안 넣어도 괜찮다"고 하면 방금 한 일을
    // 되묻는 꼴이다.
    await pump(tester, CardAddPhotoSlide(first: false, onPick: () {}));

    expect(find.text(AppStrings.recordCardPhotoEmpty), findsNothing);
  });

  testWidgets('지우기를 누르면 알린다', (tester) async {
    var removed = 0;
    await pump(tester, photoSlide(onRemove: () => removed++));

    await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
    await tester.pump();

    expect(removed, 1);
  });

  testWidgets('⚠️ 대표인 장에는 대표로 지정하라는 버튼이 없다', (tester) async {
    // 눌러도 아무 일도 없는 버튼은 고장으로 읽힌다.
    await pump(tester, photoSlide(total: 2, isCover: true));

    expect(find.text(AppStrings.recordCardPhotoMakeCover), findsNothing);
    expect(find.text(AppStrings.recordCardPhotoCover), findsOneWidget);
  });

  testWidgets('대표가 아닌 장에서는 대표로 지정할 수 있다', (tester) async {
    var made = 0;
    await pump(
      tester,
      photoSlide(index: 1, total: 2, isCover: false, onMakeCover: () => made++),
    );

    await tester.tap(find.text(AppStrings.recordCardPhotoMakeCover));
    await tester.pump();

    expect(made, 1);
  });

  testWidgets('⚠️ 한 장뿐이면 대표 이야기를 꺼내지 않는다', (tester) async {
    // 고를 것이 없는데 "대표 사진"이라고 적으면 무엇과 견준 말인지 알 수 없다.
    await pump(tester, photoSlide(total: 1));

    expect(find.text(AppStrings.recordCardPhotoCover), findsNothing);
    expect(find.text(AppStrings.recordCardPhotoMakeCover), findsNothing);
  });

  testWidgets('⚠️ 이미 올린 사진에는 밀어 보라고 하지 않는다', (tester) async {
    // 9:16으로 잘려 나가 틀 안에서 옮길 데가 없다.
    await pump(tester, photoSlide());

    expect(find.text(AppStrings.recordCardPhotoPanHint), findsNothing);
  });
}
