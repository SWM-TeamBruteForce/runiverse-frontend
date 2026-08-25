# 설정 (S22.2) 설계

프로필 탭 ⚙ 버튼으로 들어가는 설정 화면이다.
알림 허용 · 프로필 공개 범위 · 계정정보 · 비밀번호 변경 · 약관 · 로그아웃 · 회원 탈퇴를 담는다.

---

## 1. 서버 현황 — 7개 중 실제로 되는 것은 2개다

4차 API 명세서 기준이다. **이 표가 이 설계의 전제다.**

| 항목 | 엔드포인트 | 명세 | BE 현황 |
|---|---|---|---|
| 알림 허용 | `GET·PATCH /users/me/settings` → `alertConsent` | #57·#58 | ❌ 개발전 |
| 공개 범위 | 같은 API → `profileVisibility` | #57·#58 | ❌ 개발전 |
| 계정정보 | `GET /users/me/account` → `email` `loginType` | #55 | ❌ 개발전 |
| 비밀번호 변경 | `PATCH /users/me/password` | #56 | ✅ 개발완료 |
| 로그아웃 | `POST /auth/logout` | #8 | ✅ 개발완료 |
| 회원 탈퇴 | `DELETE /users/me` | **명세 없음** | ❌ 개발전 |
| 약관 | — | 문서 URL 미정 | — |

되는 둘만 만들면 화면이 절반 비어 보이고, 서버가 뜬 뒤 UI를 다시 만들게 된다.
그래서 **일곱 개를 다 그리고, 없는 것은 `FakeSettingsRepository`가 답한다.**
서버가 뜨면 `settings_provider.dart`의 한 줄을 바꾼다 — auth·profile에서 이미 쓴 방식이다.

### ⚠️ 회원 탈퇴는 명세가 없다

4차 엔드포인트 DB에 **등재되어 있지 않다.** 2.5차(과거 명세서)에 `DELETE /api/v1/users/me`가 있고,
기능정의서 `USR-ACCOUNT-001`은 그 경로를 *"권장, 실제 경로 협의 필요"*라고만 적었다.

앱은 `DELETE /api/v1/users/me`를 가정하고 만든다. **경로가 바뀔 수 있다** — 바뀌면
`HttpSettingsRepository`의 한 줄이다.

---

## 2. 화면은 하나다

정본 와이어프레임 S22.2가 한 화면이다. 기능정의서는 `SETTING-NOTIFICATION-001`,
`SETTING-VISIBILITY-001`처럼 코드를 나눠 두었지만 **그것은 기능 목록의 분류이지 화면 분할이 아니다.**
`PATCH /settings`는 필드 두 개짜리 API 하나라, 화면을 셋으로 쪼개면 같은 API를 세 군데서 부르게 된다.

```
‹  설정                                   /profile/settings
 알림
┌────────────────────────┐
│ 알림 허용           [●─]│   alertConsent
└────────────────────────┘
 ⚠ 기기 알림이 꺼져 있어요   [기기 설정 열기]   ← 권한 없을 때만

 공개 범위
 ( 전체 공개 )( 팔로워에게만 )              profileVisibility

 계정
┌────────────────────────┐
│ 이메일   run@example.com│   읽기 전용
│ 로그인          카카오   │   읽기 전용
│ 비밀번호 변경          ›│   loginType == local 일 때만
│ 약관 및 개인정보처리방침 ›│
│ 로그아웃              ›│
│ 회원 탈퇴             ›│   error 색
└────────────────────────┘
```

**탭 셸 밖에 둔다.** 프로필 편집(S22.1)과 같은 이유다 — 하단 탭이 함께 보이면
설정 도중에 다른 탭으로 샌다.

진입점은 이미 자리만 잡혀 있다: `profile_header.dart`의 `_HeaderAction(icon: LucideIcons.settings)`.
지금은 `onTap`이 없다. 여기에 붙인다.

### 정본과 다른 곳 셋

**알림 토글은 3개가 아니라 1개다.** 정본은 매칭·러닝·소셜 3종인데 API는 `alertConsent`
Boolean 하나뿐이다. 셋을 그리면 저장할 데가 없다.

**공개 범위는 3단이 아니라 2단이다.** 정본은 전체공개/팔로워공개/나만보기인데
enum은 `PUBLIC` / `FRIENDS`뿐이다.

**`FRIENDS`를 "친구"라고 부르지 않는다.** CLAUDE.md의 금지어다(요청→수락 모델).
화면에는 **"팔로워에게만"**으로 쓴다. 정본 S18도 "팔로워/팔로잉 목록"이다.

### 만들지 않는 것

- **권한 섹션**(위치·알림 상태를 나란히 보여주는 카드). 정본에 있지만 뺀다.
  위치 권한은 러닝을 시작할 때 반드시 받으므로 여기서 또 보여줄 이유가 없고,
  알림 권한은 아래 3절처럼 토글 옆에서 직접 다룬다.
- **알림 3종 분리**, **공개 범위 3단** — 위 참조.
- **탈퇴 사유 입력.** 기능정의서 제목은 "탈퇴 사유 입력 후 계정 삭제"인데
  본문의 입력은 *Access Token · 탈퇴 확인 여부(boolean)*뿐이다. 받을 곳이 없다.

---

## 3. 알림 토글은 기기 권한까지 본다

여기가 이 화면에서 가장 틀리기 쉬운 곳이다.

`alertConsent`는 **서버에 남기는 의사**고, 기기 알림 권한은 **OS가 쥔 허가**다.
명세도 *"OS 알림 권한과 별도로 적용된다"*고 적었다. 둘은 서로 모른다.
그래서 **토글 하나로 둘을 합쳐 표현하면 반드시 거짓말을 하게 된다** —
토글이 켜져 있는데 알림이 안 오는 상태가 생긴다.

토글은 `alertConsent`만 나타낸다. 대신 이렇게 잇는다.

**켤 때** — 기기 권한이 없으면 **먼저 권한을 요청한다.**
- 허용되면 서버에 `alertConsent: true`.
- 거부되면 서버에는 그대로 `true`를 보낸다. 사용자의 의사는 "받고 싶다"가 맞기 때문이다.
  대신 아래의 경고 줄이 뜬다.
- 영구 거부(다시 묻지 않음)면 요청 대화상자가 아예 안 뜬다. 이때 갈 곳이 기기 설정뿐이라
  `openAppSettings()`가 필요하다.

**상시** — `alertConsent`가 `true`인데 기기 권한이 없으면 토글 아래에
`⚠ 기기 알림이 꺼져 있어요 [기기 설정 열기]` 줄을 띄운다.

**돌아올 때** — 기기 설정에서 권한을 바꾸고 앱으로 돌아오면 화면이 그대로면 안 된다.
`AppLifecycleState.resumed`에서 권한을 다시 읽는다. **이걸 빼먹으면 사용자가
권한을 켜고 돌아왔는데도 경고 줄이 그대로 남는다.**

### ⚠️ 이 토글은 지금 아무 알림도 켜지 않는다

`alertConsent`는 서버 미배포고, FCM 같은 푸시 인프라도 아직 없다.
**실제로 동작하는 것은 기기 권한 요청뿐이다.** 화면과 저장 구조를 미리 갖춰 두는 것이
이 절의 목적이고, 푸시가 붙을 때 이 자리는 그대로 쓴다.

### 새 패키지 — `permission_handler`

알림 권한을 읽으려면 필요하다. `geolocator`는 위치 전용이라 알림 권한을 보지 못한다.
안드로이드 13+부터 `POST_NOTIFICATIONS`가 런타임 권한이다.

대안이었던 `flutter_local_notifications`는 본업이 알림을 **띄우는** 것이라,
알림을 띄우지도 않으면서 알림 라이브러리를 넣게 되고 `openAppSettings()`도 없다.

---

## 4. 토글과 칩은 낙관적으로 반영한다

누르면 **즉시 화면이 바뀌고** 뒤에서 `PATCH`를 보낸다.
실패하면 **원래 값으로 되돌리고** 스낵바를 띄운다.
스위치를 누르고 스피너를 보며 기다리는 것은 설정 화면에서 특히 나쁘다.

되돌리려면 **"보낸 값"이 아니라 "보내기 전 값"을 들고 있어야 한다.**

성공하면 응답으로 통째로 덮는다. `PATCH`는 부분 수정이어도 **갱신 후 전체 설정을 돌려주므로**,
연타해서 응답 순서가 뒤바뀌어도 마지막 응답이 화면을 정리한다.

### 화면의 세 상태

이 화면은 **두 API를 함께 기다린다**(`/account`와 `/settings`).

| 상태 | 화면 |
|---|---|
| loading | 스켈레톤. 계정 섹션은 값이 없어도 **행 자체는 보여준다** — 로그아웃·탈퇴는 서버 응답이 없어도 눌러야 한다 |
| data | 위 레이아웃 |
| error | 조회 실패 안내 + `다시 시도`. 이때도 **로그아웃은 눌린다** |

⚠️ **조회에 실패해도 로그아웃을 막지 않는다.** 세션이 이상해서 조회가 실패하는 경우가 있는데,
그때 로그아웃까지 막히면 사용자가 앱에서 나갈 방법이 없다.

`empty`는 없다. 설정은 항상 값이 있다 — 서버가 기본값(`alertConsent: true`)을 준다.

두 테마 모두 정의한다. 탈퇴 행의 `error` 색은 라이트에서 대비가 떨어지기 쉬우니
`context.appColors`의 토큰을 그대로 쓰고 별도 값을 만들지 않는다.

---

## 5. 도메인 — `lib/features/settings/`

```dart
// domain/
enum LoginType { local, google, kakao }        // 전송 키는 enum 이름과 분리한다
enum ProfileVisibility { public, followers }   // FRIENDS ↔ followers

class AccountInfo   { final String email; final LoginType loginType; }
class AppSettings   { final bool alertConsent; final ProfileVisibility visibility; }

abstract interface class SettingsRepository {
  Future<AccountInfo> fetchAccount();
  Future<AppSettings> fetchSettings();
  Future<AppSettings> updateSettings({bool? alertConsent, ProfileVisibility? visibility});
  Future<void> changePassword({required String current, required String next});
  Future<void> withdraw();
}
```

`LoginType`·`ProfileVisibility`의 전송값을 enum 이름에서 뽑지 않는다.
이름을 바꾸면 서버와의 약속이 조용히 깨진다 — `SignInMethod`에서 쓴 방식과 같다.

실패는 전부 `SettingsException`으로 던진다. 구현체가 dio 사정을 밖으로 흘리지 않는다.

비밀번호 변경만 실패 종류가 많아 따로 둔다.

| 코드 | 상태 | 뜻 |
|---|---|---|
| `INVALID_CURRENT_PASSWORD` | 401 | 현재 비밀번호가 틀렸다 |
| `PASSWORD_NOT_SET` | 409 | 소셜 계정이라 바꿀 수 없다 |
| `INVALID_REQUEST` | 400 | 형식 위반 |

### ⚠️ `INVALID_CURRENT_PASSWORD`는 401이지만 세션 만료가 아니다

401을 만나면 토큰을 갱신하고 재시도하는 인터셉터가 이미 있다.
이 코드가 거기 걸리면 **비밀번호를 틀린 사람이 조용히 재시도되고, 결국 로그아웃된다.**
`code`를 보고 갈라서 입력 오류로 처리한다. 명세에도 같은 주의가 적혀 있다.

---

## 6. 로그아웃과 탈퇴는 `SettingsRepository`를 쓰지 않는다

**로그아웃**은 이미 있는 `AuthController.signOut()`이 서버 호출 · 토큰 삭제 ·
상태 전환을 다 한다. 구현되어 있는데 **어느 화면에서도 부르지 않던** 코드다.
설정 화면이 그 자리다.

**탈퇴**는 `withdraw()`가 성공한 시점에 **서버 세션이 이미 죽어 있다.**
여기서 `signOut()`을 부르면 실패할 호출을 한 번 더 보낸다.
그래서 `AuthController`에 **서버를 부르지 않고 로컬만 비우는 경로**를 하나 더 둔다.

두 경우 모두 `AuthSignedOut(returning: true)`로 간다 — 로그아웃한 사람은 처음 온 사람이 아니다.

⚠️ 탈퇴는 **되돌릴 수 없다.** 확인 시트에서 한 번 더 묻고,
`profile_prompt_sheet.dart`가 아니라 파괴적 동작임이 드러나는 문구·색으로 만든다.

---

## 7. 약관은 행만 둔다

약관 전문 URL이 아직 없다. 가입 화면(S03)도 링크 없이 체크박스만 있고
`terms_agreement_page.dart`에 *"약관 전문 URL이 정해지면 여기 붙는다"*고 자리만 남아 있다.

URL 상수를 한 곳에 두고 **비워 둔다.** 비어 있는 동안 이 행은 눌러도 "준비 중"이 뜬다.
URL이 정해지면 상수를 채우고 그때 `url_launcher`를 넣는다 —
지금 넣으면 열 URL이 없어 죽은 코드가 된다.

---

## 8. 백엔드에 물어볼 것

1. **`DELETE /users/me` 경로 확정.** 4차 엔드포인트 DB에 없다.
2. **#55 `/users/me/account`, #57·#58 `/users/me/settings` 배포 일정.**
3. **탈퇴 시 진행 중인 예약 매칭 처리.** 기능정의서 예외 3이 *"탈퇴 진행 또는 제한"*으로
   열려 있다. 앱이 막아야 하는지 서버가 거절하는지 정해져야 한다.
4. **`GET /users/me`와 `GET /users/me/account`의 관계.** 기능정의서 `SETTING-HOME-001`은
   설정 홈의 연관 API를 `GET /users/me`로 적고 거기서 *계정 유형·알림 상태·공개 범위*를
   받는다고 했지만, **실제 응답에는 셋 다 없다**(`userId` `nickname` `isOnboarded`뿐).
   문서가 어긋나 있다. 설정 화면은 `/account`와 `/settings`를 쓴다.

---

## 9. 파일 계획

한 번에 한 파일씩 만든다.

**domain** — `login_type.dart` · `profile_visibility.dart` · `account_info.dart` ·
`app_settings.dart` · `settings_failure.dart` · `password_change_failure.dart` ·
`settings_repository.dart`

**data** — `fake_settings_repository.dart` · `http_settings_repository.dart`

**presentation** — `settings_provider.dart` · `settings_page.dart` ·
`password_change_page.dart` · `withdraw_sheet.dart`

**잇는 곳** — `app_routes.dart`(경로 2개) · `app_router.dart` · `app_strings.dart` ·
`profile_header.dart`(⚙ `onTap`) · `auth_provider.dart`(로컬만 비우는 경로) · `pubspec.yaml`

**테스트** — 설정 전이(낙관적 반영과 되돌리기) · 비밀번호 실패 분기 ·
`loginType`에 따른 메뉴 분기

파일이 20개를 넘으므로 **PR을 둘로 나눈다.**
① 도메인 + data + 설정 홈(알림·공개범위·계정·로그아웃)
② 비밀번호 변경 + 탈퇴 + 약관 행
