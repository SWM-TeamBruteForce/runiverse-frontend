# UI 전면 교체 작업 환경 구축 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 화면 20개를 하나씩 새 디자인으로 옮기기 전에, 되돌릴 자리와 회귀 감지 장치를 만든다.

**Architecture:** 되돌리기는 태그 하나와 PR 단위 revert로 한다(복제본 없음). 새 토큰은 `lib/core/theme/v2/`에 두고 옮긴 화면만 쓰며, 한 화면이 두 세대를 섞지 않는 것을 **테스트로 강제**한다. 깨진 테스트는 미리 손보지 않고 교체하는 PR 안에서 고치되, 그 방식이 실제로 통하는지 한 화면으로 먼저 확인한다.

**Tech Stack:** Flutter (fvm) · flutter_test · git

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

## Global Constraints

- 모든 flutter/dart 명령 앞에 `fvm`. 이 저장소에서는 `.\.fvm\flutter_sdk\bin\flutter.bat` 로 직접 부른다 — fvm 이 PATH 에 없다.
- 모든 커밋 시점에 `fvm flutter analyze` 경고 **0개**, `fvm flutter test` **전체 통과**.
- 커밋 메시지는 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test` `🚚 Chore` `✂️ Remove` `🔧 Rename`
- **AI 를 공동 작성자로 넣지 않는다.** `Co-Authored-By` 트레일러도 `🤖 Generated with` 푸터도 붙이지 않는다.
- 색·치수·타이포·문자열·모션은 토큰으로만 — `context.appColors` `AppSpacing` `AppRadius` `AppTypography` `AppStrings` `AppMotion`. `core/theme/tokens/` 밖에서 `Color(0x...)` 등 값 하드코딩 금지.
- UI 텍스트는 한국어. **"친구"라는 말은 쓰지 않는다.**
- 새 패키지를 추가하지 않는다. 이 계획은 기존 의존성만 쓴다.
- 브랜치는 `<type>/<domain>` 소문자 kebab-case. PR base 는 `dev`.

---

### Task 1: 되돌릴 자리를 만든다

**Files:**
- 없음 (git 태그만)

**Interfaces:**
- Consumes: 없음
- Produces: `pre-redesign` 태그 — 이후 모든 작업이 "교체 전"을 가리킬 때 쓰는 이름

- [ ] **Step 1: 지금 dev 가 어디인지 확인한다**

```bash
git fetch upstream
git log --oneline upstream/dev -1
```

Expected: `1262402 🔨 Fix: 달리는 중에 홈이 길을 잃고, 기록 오류가 뭉개지던 것을 고친다 (#83)` 또는 그 이후 커밋. 이 해시가 교체 시작점이다.

- [ ] **Step 2: 태그를 단다**

```bash
git tag pre-redesign upstream/dev
```

- [ ] **Step 3: 태그가 맞는 곳을 가리키는지 확인한다**

```bash
git log --oneline pre-redesign -1
git diff --stat pre-redesign upstream/dev
```

Expected: 첫 줄이 Step 1 과 같은 커밋. `git diff` 는 **아무것도 출력하지 않는다**(같은 지점이므로).

- [ ] **Step 4: 원격에 올린다**

```bash
git push upstream pre-redesign
```

- [ ] **Step 5: 원격에서 보이는지 확인한다**

```bash
git ls-remote --tags upstream | grep pre-redesign
```

Expected: `<해시>	refs/tags/pre-redesign` 한 줄.

커밋할 파일이 없으므로 이 작업에는 커밋이 없다.

---

### Task 2: 한 화면이 두 세대의 토큰을 섞지 못하게 막는다

스펙 3절의 **유일한 구조 규칙**을 기계가 지키게 한다. `v2` 폴더가 아직 없어도 미리 넣는다 — 첫 화면을 옮기는 순간부터 작동해야 하고, 그때 만들면 이미 섞인 뒤다.

**Files:**
- Create: `test/theme_generation_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `mixesGenerations(String source) -> bool` — 이 파일 안에서만 쓴다. 한 소스가 구·신 토큰을 함께 import 하면 `true`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/theme_generation_test.dart` 를 만든다.

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 한 소스가 **두 세대의 토큰을 함께** import 하는가.
///
/// 새 디자인으로 옮긴 화면은 `core/theme/v2/` 만 읽고, 아직 안 옮긴 화면은
/// 기존 `core/theme/tokens/`·`core/theme/extensions/` 만 읽는다. 섞이면
/// **"어디까지 옮겼나"를 코드로 답할 수 없고**, 되돌릴 때 무엇을 되돌려야
/// 하는지도 흐려진다.
bool mixesGenerations(String source) {
  final usesNew = source.contains('core/theme/v2/');
  if (!usesNew) return false;
  return source.contains('core/theme/tokens/') ||
      source.contains('core/theme/extensions/');
}

void main() {
  group('세대 판정', () {
    test('둘을 함께 쓰면 잡는다', () {
      const source = '''
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
''';

      expect(mixesGenerations(source), isTrue);
    });

    test('새 것만 쓰면 통과한다', () {
      const source = '''
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
''';

      expect(mixesGenerations(source), isFalse);
    });

    test('옛 것만 쓰면 통과한다', () {
      const source = '''
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
''';

      expect(mixesGenerations(source), isFalse);
    });

    test('확장도 구 세대로 센다', () {
      // `extensions/app_colors.dart` 만 함께 써도 섞인 것이다.
      const source = '''
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
''';

      expect(mixesGenerations(source), isTrue);
    });
  });

  test('⚠️ 섞어 쓰는 파일이 하나도 없다', () {
    // ⚠️ `lib/core/theme/` 자체는 뺀다. 새 토큰이 기존 팔레트를 재료로 쓸 수
    // 있고, 그것은 섞은 것이 아니라 얹은 것이다.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('lib/core/theme/')) continue;
      if (mixesGenerations(entity.readAsStringSync())) offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '한 화면은 한 세대만 쓴다. 옮기는 중이면 그 화면의 토큰 import 를 '
          '전부 v2 로 바꾸고, 아직이면 전부 기존 것으로 되돌린다.',
    );
  });
}
```

- [ ] **Step 2: 테스트를 돌려 판정 로직이 실제로 잡는지 본다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/theme_generation_test.dart
```

Expected: **5개 전부 통과.** `세대 판정` 4개가 통과하면 판정 로직이 섞인 것을 잡는다는 뜻이고, 마지막 하나는 지금 `v2` 가 없으므로 위반이 없어 통과한다.

⚠️ 마지막 테스트가 지금 **아무것도 안 걸러도 정상**이다. 앞의 4개가 "이 판정은 실제로 실패할 수 있다"를 증명하는 자리다.

- [ ] **Step 3: 스캔이 진짜로 파일을 읽는지 확인한다**

판정 로직이 아니라 **스캔 자체**가 도는지 본다. 일부러 위반 파일을 만든다.

```powershell
New-Item -ItemType Directory -Force lib/core/widgets/v2 | Out-Null
@'
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
'@ | Out-File -Encoding utf8 lib/core/widgets/v2/_scan_probe.dart
.\.fvm\flutter_sdk\bin\flutter.bat test test/theme_generation_test.dart
```

Expected: **`⚠️ 섞어 쓰는 파일이 하나도 없다` 가 실패**하고, 실패 메시지에 `lib/core/widgets/v2/_scan_probe.dart` 가 보인다.

- [ ] **Step 4: 탐침을 지우고 다시 통과시킨다**

```powershell
Remove-Item -Recurse -Force lib/core/widgets/v2
.\.fvm\flutter_sdk\bin\flutter.bat test test/theme_generation_test.dart
```

Expected: 5개 전부 통과.

- [ ] **Step 5: 전체 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format test/theme_generation_test.dart
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 테스트 **914개 통과**(기존 909 + 새 5).

- [ ] **Step 6: 커밋**

```bash
git checkout -b test/theme-generation-guard
git add test/theme_generation_test.dart
git commit -F - <<'EOF'
✅ Test: 한 화면이 두 세대의 토큰을 섞지 못하게 막는다

디자인을 화면 하나씩 옮기는 동안 새 토큰(`core/theme/v2/`)과 기존
토큰이 함께 존재한다. 한 화면이 둘을 섞으면 "어디까지 옮겼나"를 코드로
답할 수 없고, 되돌릴 때 무엇을 되돌려야 하는지도 흐려진다.

`v2` 폴더가 생기기 전에 넣는다. 첫 화면을 옮기는 순간부터 작동해야
하고, 그때 만들면 이미 섞인 뒤다.

지금은 걸러낼 것이 없어 조용히 통과한다. 판정이 실제로 섞인 것을
잡는다는 것은 앞의 네 테스트가 증명한다.
EOF
```

---

### Task 3: 테스트 전환 방식이 실제로 통하는지 한 화면으로 확인한다

스펙 5절은 "깨진 테스트를 교체 PR 안에서 고친다"로 갔다. **그 고치는 방식이 정말 그물을 유지하는지**를 디자인 없이 먼저 확인한다.

대상은 `profile_edit_page_test.dart` 다. 구조 결합 11건 중 **4건은 화면 클래스라 살아남고, 7건이 위태롭다**(저장 버튼 2 · `TextField` 5). 실험 크기로 맞고, 프로필 편집은 다른 화면과 얽히지 않는다.

**Files:**
- Modify: `lib/features/profile/presentation/profile_edit_page.dart` — 소개글 입력에 키를 단다
- Modify: `test/profile_edit_page_test.dart:92-95` — 저장 버튼 단정을 동작으로 옮긴다
- Modify: `test/profile_edit_page_test.dart:107,116,128,140,171` — `find.byType(TextField)` 를 키로 옮긴다

**Interfaces:**
- Consumes: Task 2 의 `test/theme_generation_test.dart` (무관하게 통과해야 한다)
- Produces: `ProfileEditPage` 소개글 입력의 `ValueKey('profile-introduction')` — **새 디자인이 이 키를 이어받아야 테스트가 산다.** 이후 화면 교체 PR 이 지켜야 할 계약이다.

- [ ] **Step 1: 지금 상태를 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/profile_edit_page_test.dart
```

Expected: **9개 통과.** 여기서부터 시작한다.

- [ ] **Step 2: 소개글 입력에 키를 단다**

`lib/features/profile/presentation/profile_edit_page.dart` 의 320행 `AppInput` 에 `key` 를 더한다.

```dart
                      AppInput(
                        // ⚠️ **테스트가 이 입력을 찾는 유일한 손잡이다.**
                        // 부품이 `TextField` 인지 무엇인지에 기대면 디자인을
                        // 바꿀 때 테스트가 통째로 깨진다. 디자인을 바꿔도
                        // **이 키는 이어받는다.**
                        key: const ValueKey('profile-introduction'),
                        controller: _introduction,
                        hint: AppStrings.profileIntroductionHint,
```

- [ ] **Step 3: 키가 실제로 닿는지 테스트 하나로 먼저 확인한다**

`test/profile_edit_page_test.dart` 의 `소개글을 고치면 저장이 열린다` 하나만 바꾼다.

```dart
  testWidgets('소개글을 고치면 저장이 열린다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isTrue);
  });
```

그리고 파일 위쪽 `saveButton()` 옆에 손잡이를 더한다.

```dart
  /// 소개글 입력. **부품 타입이 아니라 키로 찾는다** — 디자인을 바꿔도 키만
  /// 이어받으면 이 테스트가 산다.
  final introductionField = find.byKey(const ValueKey('profile-introduction'));
```

- [ ] **Step 4: 그 테스트만 돌려 키가 닿는지 본다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/profile_edit_page_test.dart --plain-name "소개글을 고치면 저장이 열린다"
```

Expected: **통과.** 실패하면 키가 `AppInput` 안쪽의 `TextField` 까지 안 내려간 것이다 — 그때는 `AppInput` 이 `key` 를 어디에 붙이는지 보고 `TextField` 쪽으로 옮긴다.

- [ ] **Step 5: 남은 네 곳의 `find.byType(TextField)` 를 키로 바꾼다**

107·116·128·140·171 행의 `find.byType(TextField)` 를 전부 `introductionField` 로 바꾼다. 다섯 곳 모두 같은 입력을 가리킨다.

```dart
    await tester.enterText(introductionField, '즐겁게 달려요');
```

- [ ] **Step 6: 저장 버튼 단정을 동작으로 옮긴다**

92-95 행을 바꾼다.

```dart
  /// 저장 버튼. **문구로 찾는다** — `TextButton` 인지 무엇인지에 기대지 않는다.
  Finder saveButton() => find.text(AppStrings.profileEditSave);

  /// 저장이 열려 있는가. **부품의 `onPressed` 를 보지 않는다.**
  ///
  /// 눌러 보고 **서버로 나갔는지**로 판단한다. 잠김은 부품의 속성이 아니라
  /// 화면의 약속이고, 디자인이 바뀌어도 그 약속은 그대로다.
  Future<bool> saveOpens(WidgetTester tester) async {
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    return repo.updated != null;
  }
```

`⚠️ 바꾼 게 없으면 저장이 잠긴다` 와 `소개글을 고치면 저장이 열린다` 를 그것으로 다시 쓴다.

```dart
  testWidgets('⚠️ 바꾼 게 없으면 저장이 잠긴다', (tester) async {
    await pumpEdit(tester);

    // 열자마자 눌리면 아무것도 안 바꾸고 요청이 나간다.
    expect(await saveOpens(tester), isFalse);
  });

  testWidgets('소개글을 고치면 저장이 열린다', (tester) async {
    await pumpEdit(tester);

    await tester.enterText(introductionField, '즐겁게 달려요');
    await tester.pumpAndSettle();

    expect(await saveOpens(tester), isTrue);
  });
```

- [ ] **Step 7: 전환한 테스트가 통과하는지 본다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/profile_edit_page_test.dart
```

Expected: **9개 전부 통과.**

- [ ] **Step 8: ⚠️ 여전히 고장을 잡는지 확인한다 — 이 작업의 핵심**

통과만 하는 테스트는 그물이 아니라 장식이다. **일부러 화면을 고장 내서** 빨개지는지 본다.

`lib/features/profile/presentation/profile_edit_page.dart:106` 의 잠금 조건에서 `_dirty` 를 뺀다.

```dart
  bool get _canSave =>
      !_saving && !_introductionTooLong && !_birthdayTooYoung;
```

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/profile_edit_page_test.dart --plain-name "바꾼 게 없으면 저장이 잠긴다"
```

Expected: **실패한다.** 통과하면 전환이 단정을 느슨하게 만든 것이니 Step 6 으로 돌아간다.

- [ ] **Step 9: 고장을 되돌린다**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib/features/profile/presentation/profile_edit_page.dart
```

`_canSave` 를 원래대로 되돌린다.

```dart
  bool get _canSave =>
      _dirty && !_saving && !_introductionTooLong && !_birthdayTooYoung;
```

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/profile_edit_page_test.dart
```

Expected: 9개 전부 통과.

- [ ] **Step 10: 전체 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, **914개 통과**.

- [ ] **Step 11: 커밋**

```bash
git add lib/features/profile/presentation/profile_edit_page.dart test/profile_edit_page_test.dart
git commit -F - <<'EOF'
✅ Test: 프로필 편집 테스트를 화면 구조에서 떼어낸다

디자인을 갈아끼울 때 깨질 단정을 미리 한 화면에서 옮겨 본다. 이 방식이
정말 그물을 유지하는지 확인하는 것이 목적이다.

저장 버튼은 `TextButton` 타입과 `onPressed` 를 보고 있었다. 눌러 보고
서버로 나갔는지로 바꾼다 — 잠김은 부품의 속성이 아니라 화면의 약속이고,
디자인이 바뀌어도 그 약속은 그대로다.

소개글 입력은 `find.byType(TextField)` 로 찾고 있었다. 키를 달고 그것으로
찾는다. 새 디자인은 이 키를 이어받아야 한다.

일부러 잠금 조건을 부수어 테스트가 빨개지는 것을 확인했다. 느슨해져서
통과만 하는 것이 아니라 여전히 고장을 잡는다.
EOF
```

---

### Task 4: 확인한 것을 스펙에 적고 PR 을 낸다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md` — 5절에 전환 실측을 더한다

**Interfaces:**
- Consumes: Task 2·3 의 결과
- Produces: 없음 (문서)

- [ ] **Step 1: 스펙 5절에 실측을 더한다**

`### 판정 기준` 절 **뒤에** 붙인다.

```markdown
### 먼저 해 본 한 화면

`profile_edit_page_test` 로 전환 방식을 확인했다(2026-09-25).

- 구조 결합 11건 중 **4건은 화면 클래스라 손댈 필요가 없었고**, 7건만 옮겼다
- 저장 버튼 2건은 `tester.widget<TextButton>(…).onPressed` 에서 **눌러 보고
  서버로 나갔는지**로 옮겼다
- 소개글 입력 5건은 `find.byType(TextField)` 에서 **키**(`ValueKey('profile-introduction')`)로
  옮겼다. 입력은 문구로 찾기 어렵다 — 힌트는 비었을 때만 보인다

⚠️ **키는 계약이다.** 그 화면을 새 디자인으로 옮길 때 키를 이어받지 않으면
테스트가 깨진다. 화면 교체 PR 마다 확인한다.

전환 뒤 잠금 조건을 일부러 부수어 테스트가 빨개지는 것을 확인했다. 느슨해져
통과만 하는 상태가 아니다.
```

- [ ] **Step 2: 형식을 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 914개 통과.

- [ ] **Step 3: 커밋**

```bash
git add docs/specs/2026-09-25-ui-redesign-workspace-design.md
git commit -m "📝 Docs: 테스트 전환을 한 화면으로 먼저 해 본 결과를 적는다"
```

- [ ] **Step 4: 브랜치를 올린다**

```bash
git push -u origin test/theme-generation-guard
```

- [ ] **Step 5: PR 을 연다**

```bash
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend \
  --base dev --head jihwanjo-98:test/theme-generation-guard \
  --title "✅ Test: UI 교체에 대비해 회귀 감지 장치를 만든다"
```

본문은 `.github/pull_request_template.md` 의 여섯 절을 채운다. **💬 리뷰 포인트**에는 다음을 적는다.

- 세대 혼용 테스트가 지금은 걸러낼 것이 없어 조용히 통과한다. 판정이 실제로 동작한다는 것은 앞의 네 테스트가 증명한다 — 이 구조가 괜찮은지
- 입력을 키로 찾게 한 것. 키를 새 디자인이 이어받아야 하는 계약이 생겼는데, 그 계약을 문서 말고 기계로 강제할 방법이 있는지

- [ ] **Step 6: base 가 `dev` 인지 확인한다**

```bash
gh pr view --repo SWM-TeamBruteForce/runiverse-frontend --json baseRefName -q .baseRefName
```

Expected: `dev`. GitHub 는 `main` 을 기본으로 잡으므로 반드시 확인한다.

---

## 이 계획이 다루지 않는 것

**화면 교체 자체는 여기 없다.** 토큰 값도 화면 구성도 Figma 에서 오는데 아직 링크를 받지 않았다. 그것을 "Figma 보고 채움"으로 적으면 계획이 아니라 빈칸이 된다.

Figma 를 받으면 **두 번째 계획**을 쓴다. 그 계획이 다룰 것:

- `lib/core/theme/v2/` 의 실제 토큰 값
- 파일럿 화면 확정과 교체 (스펙 6절 — `settings_page` 는 테스트 결합이 1건뿐이라 절차 검증용으로는 배우는 것이 적다. `profile_edit_page` 는 Task 3 에서 이미 손봤으므로 그 화면이 유력하다)
- 나머지 19개 화면의 순서 — 부품을 많이 공유하는 화면끼리 묶어 `widgets/v2` 를 두 번 만들지 않게 한다
- 마지막 화면을 옮긴 뒤의 정리 (스펙 7절) — 옛 `theme/`·`widgets/` 를 지우고 `v2/` 를 본래 자리로 올린다. 그 시점에 Task 2 의 세대 혼용 테스트도 역할이 끝나므로 같이 지운다
