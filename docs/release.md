# Release — 빌드와 배포

dev 앱을 팀에 나눠 주고 운영 앱을 스토어에 올리는 절차. 콘솔(Play·카카오·구글)에서
키를 등록하는 화면별 절차는 노션에 둔다.

---

## flavor — 앱 두 벌

| | `dev` | `prod` |
|---|---|---|
| 패키지 | `com.runiverse.app.dev` | `com.runiverse.app` |
| 런처 이름 | Runiverse-dev | Runiverse |
| 서버 | dev 서버 (`config/dev.json`) | 운영 서버 (`config/prod.json`) |
| 업로드 키 | `android/key-dev.properties` | `android/key.properties` |
| Play 트랙 | `Runiverse-dev` 앱의 내부 테스트 | 운영 앱의 내부 테스트 → 프로덕션 |

- 기본 flavor는 `dev`다(`pubspec.yaml`의 `default-flavor`). 개발은 지금처럼
  `fvm flutter run`이면 된다. **운영 빌드만 `--flavor prod`를 붙인다.**
- iOS도 같은 이름의 스킴(`dev`·`prod`)이 있고 번들 ID·표시 이름이 위 표와 같다. dev 앱은 App Store Connect의
  `Runiverse-dev` 앱 TestFlight로, 운영 앱은 `Runiverse` 앱 TestFlight로 나간다(아래 CI).
- 두 앱은 패키지가 달라 한 기기에 나란히 깔린다. 단 로컬 dev 빌드(debug 키)와
  Play에서 받은 dev 앱(Play 키)은 같은 패키지라 덮어쓰지 못한다 — 지우고 깐다.
- 키가 없으면 debug 키로 서명된다. 빌드는 되지만 Play가 받지 않는다.

## 키 파일 놓는 곳

업로드 키는 담당자에게 따로 받는다(저장소·노션에 올리지 않는다). 넷 다 gitignore 대상이다.

```
android/key.properties          android/app/upload-keystore.jks
android/key-dev.properties      android/app/upload-keystore-dev.jks
```

- `storeFile`에는 파일 이름만 적는다(`storeFile=upload-keystore-dev.jks`). Gradle은 `android/app/`
  기준으로 찾는다. `~/`는 Gradle이 펼치지 못해 쓸 수 없다.
- **원본은 저장소 밖에 따로 백업한다.** `git clean -fdx` 한 번이면 `android/app/`의 jks가 지워진다.
  업로드 키를 잃으면 Play에 재설정을 요청해야 한다.

Firebase 설정 파일도 같은 취급이다. flavor 폴더에 두면 빌드가 알아서 집는다.

```
android/app/src/dev/google-services.json     ios/Runner/Firebase/dev/GoogleService-Info.plist
android/app/src/prod/google-services.json    ios/Runner/Firebase/prod/GoogleService-Info.plist
```

- Firebase 콘솔 → `runiverse-dev`·`runiverse` 프로젝트 → 프로젝트 설정 → 해당 플랫폼 앱의 구성 파일을 받는다.
- iOS는 `Copy Firebase Config` 빌드 단계가 구성 이름(`Debug-dev`·`Release-dev`처럼 dev가 들어 있으면 dev, 아니면 prod)으로 골라 앱에 복사한다.
  파일이 없으면 빌드가 그 자리에서 멈춘다.
- iOS 카카오·구글 로그인 복귀 스킴은 `Add URL Schemes` 빌드 단계가 `config/*.json`의 `KAKAO_NATIVE_APP_KEY`·`GOOGLE_IOS_CLIENT_ID`로
  `Info.plist`에 넣는다. 값이 없으면 경고만 남기고 빌드는 된다(그 로그인만 안 된다).
- Meta 앱 ID·클라이언트 토큰도 같은 단계가 `META_APP_ID`·`META_CLIENT_TOKEN`으로 `Info.plist`에 넣는다. Android는
  `-PMETA_APP_ID`·`-PMETA_CLIENT_TOKEN`으로 넘긴다(`flutter run`도 `-P`를 받는다). 키가 없으면 앱이 Meta를 시작하지 않는다.
  로컬에는 dev Meta 앱 값을 넣는다 — 운영 값을 넣으면 개발 중 신호가 광고 수치에 섞인다.
- iOS 릴리스 빌드는 마지막 `Upload Crashlytics Symbols` 빌드 단계가 dSYM을 Crashlytics에 올린다. 앱에 복사된
  `GoogleService-Info.plist`를 읽으므로 flavor를 따라간다. 스크립트를 못 찾으면 경고만 남기고 빌드는 된다(오류 위치만 못 읽는다).
  Android는 Crashlytics Gradle 플러그인이 릴리스 빌드의 매핑 파일을 올린다.

## dev 앱 — CI가 올린다

`.github/workflows/dev-release.yml`이 dev 브랜치의 같은 커밋을 빌드해 Android는 Play 내부 테스트,
iOS는 TestFlight에 올린다. 두 job은 따로 돌아 한쪽이 실패해도 다른 쪽은 올라간다.

- **올리기**: Actions → Dev Release → Run workflow(브랜치는 `dev`, 다른 브랜치면 멈춘다). 테스트가 필요한 사람이 누르고 두 플랫폼 결과까지 확인한다. 10~15분 뒤 테스터 폰에 업데이트가 온다
  (iOS는 업로드 뒤 TestFlight 처리가 끝나면 내부 그룹 `완전탐색`에 자동 배포된다).
- 머지마다 돌리지 않는다. 하루에 머지가 십수 번 몰려 테스터 앱이 계속 바뀐다.
- 같은 커밋도 누를 때마다 새 번호로 다시 올라간다. 서버 주소나 키만 바꿨을 때도 그냥 누르면 된다.
- 버전 코드(iOS 빌드 번호)는 실행 번호(`github.run_number`)다. 어느 커밋인지는 같은 번호의 Actions 실행에서 본다.
- **dev 앱은 스토어에 직접 올리지 않고 Run workflow로만 올린다.** 손으로 올린 번호를 CI가 따라잡을 때까지 업로드가 거절된다.
- **Re-run은 실행 번호가 같아 버전 코드가 겹친다.** 한쪽만 실패했으면 Re-run failed jobs로 그쪽만 다시 돌린다.
  이미 올라간 쪽까지 다시 돌리면 번호가 겹쳐 거절된다. 업로드 단계에서 실패했으면 먼저 Play 내부 테스트·TestFlight에
  그 번호가 들어왔는지 보고, 없을 때만 다시 돌린다. 둘 다 새로 올리려면 Run workflow로 새로 돌린다.
- 빌드 전에 `flutter analyze`·`flutter test`를 돌린다. 실패하면 두 플랫폼 다 빌드하지 않는다.
- 업로드 전에 검사하고, 하나라도 틀리면 멈춘다. Android는 패키지·debuggable·Meta 앱 ID·클라이언트 토큰·서명 지문·서버 주소,
  iOS는 번들 ID·빌드 번호·배포 서명·애플 로그인·푸시 권한·카카오·구글 복귀 스킴·Firebase 설정·Meta 앱 ID·클라이언트 토큰·추적 허용 문구·서버 주소.
- iOS는 프로젝트의 자동 서명 대신 배포 인증서·프로파일로 서명한다(CI 머신은 매번 새로 떠서, 자동 서명이면 실행마다 개발 인증서가 새로 생긴다).
  **인증서와 프로파일은 1년마다 만료된다.** 만료되면 개발자 포털에서 새로 만들어 아래 Secret을 바꾼다.

CI에 필요한 값은 저장소 Settings → Environments → **`dev`** 에 있다. 이름은 `config/*.json`의
키와 같게 두고, 운영 CI는 `prod` 환경에 같은 이름으로 둔다(아래). 값 자체는 문서에 적지 않는다.
`dev` 환경은 dev 브랜치에서만 쓸 수 있다.

| 종류 | 이름 | 내용 |
|---|---|---|
| Secret | `UPLOAD_KEYSTORE_BASE64` · `UPLOAD_KEYSTORE_PASSWORD` | dev 업로드 키 |
| Secret | `KAKAO_NATIVE_APP_KEY` · `NAVER_MAP_CLIENT_ID` · `GOOGLE_SERVER_CLIENT_ID` · `GOOGLE_IOS_CLIENT_ID` | `config/dev.json`과 같은 값 |
| Secret | `GOOGLE_SERVICES_JSON` | Firebase `runiverse-dev`의 `google-services.json`. CI가 `android/app/src/dev/`에 둔다 |
| Secret | `GOOGLE_SERVICE_INFO_PLIST` | Firebase `runiverse-dev`의 `GoogleService-Info.plist`. CI가 `ios/Runner/Firebase/dev/`에 둔다 |
| Secret | `META_APP_ID` · `META_CLIENT_TOKEN` | dev용 Meta 개발자 앱의 앱 ID와 클라이언트 토큰(앱 설정 → 고급) |
| Secret | `PLAY_SERVICE_ACCOUNT_JSON` | `Runiverse-dev` 앱에만 출시 권한이 있는 서비스 계정 |
| Secret | `IOS_DIST_CERT_BASE64` · `IOS_DIST_CERT_PASSWORD` | Apple Distribution 인증서(개인 키 포함 p12) |
| Secret | `IOS_PROFILE_BASE64` | `com.runiverse.app.dev`의 App Store 배포 프로파일 |
| Secret | `ASC_KEY_ID` · `ASC_ISSUER_ID` · `ASC_KEY_P8` | App Store Connect API 키. TestFlight 업로드에 쓴다 |
| Variable | `API_BASE_URL` | dev 서버 공개 주소 |
| Variable | `UPLOAD_CERT_SHA1` | dev 업로드 키의 SHA-1 지문. 공개값이라 Secret이 아니다. 다른 키로 서명되면 업로드 전에 멈춘다 |

## 운영 앱 — main 머지가 올린다

`.github/workflows/prod-release.yml`이 main의 커밋을 빌드해 Android는 운영 앱의 Play 내부 테스트,
iOS는 TestFlight에 올린다. 여기까지가 자동이고, **스토어 공개는 사람이 한다.**

- **올리기**: dev→main PR을 머지하면 돈다. 다시 올려야 할 때만 Actions → Prod Release → Run workflow
  (브랜치는 `main`, 다른 브랜치면 멈춘다).
- **버전 이름은 dev→main PR 전에 `pubspec.yaml`에서 올린다.** 직전 main보다 높지 않거나 `x.y.z`가
  아니면 빌드 전에 멈춘다. 자리마다 숫자로 비교한다(`1.10.0`이 `1.9.0`보다 높다). 왜 올려야 하는지는 아래 버전 절.
- 버전 코드(iOS 빌드 번호)는 dev처럼 실행 번호이고 두 플랫폼이 같다. 어느 커밋인지는 같은 번호의 Actions 실행에서 본다.
- 검사와 업로드 전 검사는 dev와 같다. 운영은 서버 주소가 정확히 `https://api.runiverseapp.com`인지,
  iOS Firebase 설정의 번들 ID가 `com.runiverse.app`인지, 구글 iOS·서버 클라이언트가 같은 프로젝트인지 더 본다.
- **운영 앱도 스토어에 직접 올리지 않는다.** 손으로 올린 번호를 CI가 따라잡을 때까지 업로드가 거절된다.

올라간 뒤 공개까지:

| | Android | iOS |
|---|---|---|
| 자동 | 내부 테스트 — 심사 없이 바로 팀원 폰에 온다 | TestFlight 처리 뒤 내부 그룹 `완전탐색`에 자동 배포 |
| 사람 | Play Console에서 그 출시를 프로덕션으로 승급(출시 노트) → Google 심사 → 게시 개요에서 「게시」(관리형 게시) | App Store Connect에서 빌드를 골라 심사 제출 → 승인 뒤 「출시」(수동 출시) |

- 두 플랫폼은 따로 공개한다. 한쪽만 내도 된다.
- 공개한 뒤 백엔드에 알려 서버의 최신 버전(`app_versions`)을 올린다.

### 운영에서 하지 말 것

- **Play Console 게시 개요에 검토 중이거나 아직 보내지 않은 변경사항이 있으면 main에 머지하지 않는다.
  Run workflow·Re-run도 누르지 않는다.** 프로덕션 출시뿐 아니라 트랙 일시중지·스토어 등록정보 같은 변경도 해당한다.
  내부 테스트에 올리는 것만으로 앱의 진행 중인 심사가 취소되고 다시 제출된다(Play API 기본 동작이고, 업로드 액션은 이를 바꾸는 옵션을 넘기지 않는다).
- 심사에 보내기 전에 Actions에서 실행 중이거나 대기 중인 Prod Release가 없는지 본다. 머지 직후 돌던 실행이 심사 중에 올리면 같은 일이 생긴다.
- **Re-run은 실행 번호가 같아 버전 코드가 겹친다.** 한쪽만 실패했으면 Re-run failed jobs로 그쪽만 다시 돌린다.
  이미 올라간 쪽까지 다시 돌리면 번호가 겹쳐 거절된다. 업로드 단계에서 실패했으면 먼저 Play 내부 테스트·TestFlight에
  그 번호가 들어왔는지 보고, 없을 때만 다시 돌린다.
- 코드를 고쳐야 하는 실패면(검사·빌드·산출물 검증 어디서든) 고쳐서 dev→main을 다시 머지한다. 이때 버전 이름도
  다시 올린다 — 실패한 머지 커밋이 직전 main으로 남아 그것과 비교하기 때문이다. 나가지 않은 번호를 건너뛰어도 문제없다.
- 성공한 실행을 Run workflow로 또 돌리지 않는다. 같은 버전 이름이 새 버전 코드로 한 번 더 올라간다.

운영 값은 Settings → Environments → **`prod`** 에 dev와 같은 이름으로 있다. `prod` 환경은 main 브랜치에서만 쓸 수 있다.
dev와 값이 같은 건 `ASC_ISSUER_ID`(팀 공통)뿐이고, 나머지는 운영용을 따로 만들었다. 다른 값은 이렇다.

| 이름 | 운영 값 |
|---|---|
| `UPLOAD_KEYSTORE_BASE64` · `UPLOAD_KEYSTORE_PASSWORD` · `UPLOAD_CERT_SHA1` | 운영 업로드 키(별칭 `upload`)와 그 지문 |
| `KAKAO_NATIVE_APP_KEY` · `NAVER_MAP_CLIENT_ID` · `GOOGLE_SERVER_CLIENT_ID` · `GOOGLE_IOS_CLIENT_ID` | `config/prod.json`과 같은 값 |
| `GOOGLE_SERVICES_JSON` · `GOOGLE_SERVICE_INFO_PLIST` | Firebase `runiverse` 프로젝트의 구성 파일 |
| `META_APP_ID` · `META_CLIENT_TOKEN` | 운영 Meta 개발자 앱 `runiverse`의 앱 ID와 클라이언트 토큰 |
| `PLAY_SERVICE_ACCOUNT_JSON` | 운영 앱에만 테스트 트랙 출시 권한이 있는 서비스 계정. 프로덕션 출시 권한은 없다 |
| `IOS_DIST_CERT_BASE64` · `IOS_DIST_CERT_PASSWORD` | 운영용 Apple Distribution 인증서(개인 키 포함 p12) |
| `IOS_PROFILE_BASE64` | `com.runiverse.app`의 App Store 배포 프로파일. 위 운영 인증서로 만든다 |
| `ASC_KEY_ID` · `ASC_KEY_P8` | 운영용 App Store Connect API 키 |
| `API_BASE_URL` | 운영 서버 주소. 워크플로가 `https://api.runiverseapp.com`과 다르면 멈춘다 |

## 손으로 빌드하기

로컬 확인용으로 쓴다. Play·TestFlight에 올리는 건 두 앱 다 CI만 한다(위). **`fvm flutter`로 빌드한다** — 전역 `flutter`는 버전이 다를 수 있다.

```bash
KAKAO=$(python3 -c "import json;print(json.load(open('config/dev.json'))['KAKAO_NATIVE_APP_KEY'])")

# dev — 실기기용은 서버 주소를 dev 서버 공개 주소로 덮어쓴다(같은 키는 --dart-define이 이긴다)
fvm flutter build appbundle --release --flavor dev --build-number=<N> \
  --dart-define-from-file=config/dev.json \
  --dart-define=API_BASE_URL=<dev 서버 공개 주소> \
  -PKAKAO_NATIVE_APP_KEY="$KAKAO"

# prod — config/prod.json의 카카오 키로 KAKAO를 다시 읽는다
fvm flutter build appbundle --release --flavor prod --build-number=<N> \
  --dart-define-from-file=config/prod.json \
  -PKAKAO_NATIVE_APP_KEY="$KAKAO"
```

산출물은 `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`다.
위 명령은 Meta 키를 `-P`로 넘기지 않아 Android에서 Meta가 시작하지 못한다(앱은 돈다). Meta까지 확인하려면
`-PMETA_APP_ID`·`-PMETA_CLIENT_TOKEN`을 같이 넘긴다.

## 버전

- **`pubspec.yaml`에는 버전 이름(`1.0.0`)만 둔다.** 버전 코드(`+N`)는 적지 않고
  빌드할 때 `--build-number`로 넘긴다. 번호를 올리려고 커밋하지 않는다.
- 버전 코드는 CI가 정한다 — 두 앱 다 그 워크플로의 실행 번호다. Play에 한 번 올린 번호는 다시 쓸 수 없다.
- 태그는 달지 않는다. 스토어에 있는 빌드가 어느 커밋인지는 같은 번호의 Actions 실행에서 찾는다.

### ⚠️ 운영 릴리스마다 버전 **이름**을 올린다

**서버가 구버전을 막는 기준이 버전 이름이다**(`X-App-Version`, API 명세서 공통
규칙). 코드(`+N`)가 아니다.

이름을 그대로 두고 여러 번 내면 **서버가 그 릴리스들을 구별하지 못한다.** 그중
하나만 막고 싶어도 방법이 없고, 최소 버전을 올리는 순간 셋 다 막힌다.

- 운영에 낼 때마다 dev→main PR 전에 `pubspec.yaml`의 `x.y.z`를 올린다. 안 올렸으면 운영 CI가 멈춘다.
- 올린 뒤에는 **백엔드에 알린다.** 최소·최신 버전은 서버 DB(`app_versions`)에
  있고 앱이 바꾸지 못한다.
- 강제 업데이트를 걸려면 **스토어 심사가 끝나 내려받을 수 있게 된 뒤에**
  `minimumVersion`을 올린다. 먼저 올리면 받을 수 있는 버전이 없는데 앱이
  막힌다.

## 업로드 전 확인

CI가 하는 검사와 같다. 손으로 빌드했으면 직접 본다.

- 패키지: dev는 `.dev`가 붙고 prod는 붙지 않는다
- `android:debuggable="true"`가 없다
- 서명 지문이 그 flavor의 업로드 키다 — `keytool -printcert -jarfile <aab>`
- 앱에 들어간 서버 주소가 맞다 — `libapp.so`를 `strings`로 본다

## 소셜 로그인 키

Play는 앱을 구글이 가진 **앱 서명 키**로 다시 서명해 내려준다. 양자 대비 하이브리드
서명이라 키가 3개(`deployment`·`hybrid_classical`·`hybrid_pqc`)이고, Play 문서대로
**셋 다** 등록한다.

- 카카오: 플랫폼 키의 Android 키 해시에 3개(SHA-1을 Base64로).
- 구글: Android OAuth 클라이언트는 SHA-1을 하나만 받으므로 키마다 하나씩, 3개.
- **업로드 키는 등록하지 않는다.** Play로 받은 앱에는 업로드 키 서명이 남지 않는다.
  로컬 빌드로 로그인을 시험할 일이 생기면 그때 추가한다.
- dev는 팀원 debug 키도 등록한다(로컬 개발용).

지문은 Play 콘솔 → 앱 무결성 → 앱 서명에서 인증서를 내려받아 확인한다.
