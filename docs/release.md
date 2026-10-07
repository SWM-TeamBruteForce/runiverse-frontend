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
| Play 트랙 | `Runiverse-dev` 앱의 내부 테스트 | 비공개 테스트 → 프로덕션 |

- 기본 flavor는 `dev`다(`pubspec.yaml`의 `default-flavor`). 개발은 지금처럼
  `fvm flutter run`이면 된다. **운영 빌드만 `--flavor prod`를 붙인다.**
- iOS도 같은 이름의 스킴(`dev`·`prod`)이 있고 번들 ID·표시 이름이 위 표와 같다. iOS 출시 준비(서명·TestFlight)는 아직이다.
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

## dev 앱 — CI가 올린다

`.github/workflows/dev-internal-release.yml`이 dev 브랜치를 빌드해 내부 테스트에 올린다.

- **지금 올리기**: Actions → Dev Internal Release → Run workflow. 10~15분 뒤 테스터 폰에 업데이트가 온다.
- **매일 03:00 KST**: 지난 하루 dev에 커밋이 있으면 자동으로 돈다.
- 머지마다 돌리지 않는다. 하루에 머지가 십수 번 몰려 테스터 앱이 계속 바뀐다.
- 버전 코드는 실행 번호(`github.run_number`)다. 출시명 `3 (dev a1b2c3d)`의 해시가 들어간 커밋이다.
  처음 손으로 올린 1·2는 첫 두 실행을 취소해 건너뛰었다(취소한 실행도 번호를 쓴다).
- **dev 앱은 손으로 올리지 않는다.** 손으로 올린 번호를 CI가 따라잡을 때까지 업로드가 거절된다. 급하면 Run workflow를 누른다.
- **Re-run은 실행 번호가 같아 버전 코드가 겹친다.** 다시 올리려면 Run workflow로 새로 돌린다.
- 업로드 전에 패키지·debuggable·서명 지문·서버 주소를 검사하고, 하나라도 틀리면 멈춘다.

CI에 필요한 값은 저장소 Settings → Environments → **`dev`** 에 있다. 이름은 `config/*.json`의
키와 같게 두고, 운영 CI를 붙일 때 `prod` 환경에 같은 이름으로 둔다. 값 자체는 문서에 적지 않는다.

| 종류 | 이름 | 내용 |
|---|---|---|
| Secret | `UPLOAD_KEYSTORE_BASE64` · `UPLOAD_KEYSTORE_PASSWORD` | dev 업로드 키 |
| Secret | `KAKAO_NATIVE_APP_KEY` · `NAVER_MAP_CLIENT_ID` · `GOOGLE_SERVER_CLIENT_ID` | `config/dev.json`과 같은 값 |
| Secret | `GOOGLE_SERVICES_JSON` | Firebase `runiverse-dev`의 `google-services.json`. CI가 `android/app/src/dev/`에 둔다 |
| Secret | `PLAY_SERVICE_ACCOUNT_JSON` | `Runiverse-dev` 앱에만 출시 권한이 있는 서비스 계정 |
| Variable | `API_BASE_URL` | dev 서버 공개 주소 |

## 손으로 빌드하기

운영 앱, 그리고 로컬 확인용으로 쓴다. dev 앱을 Play에 올리는 건 CI만 한다(위). **`fvm flutter`로 빌드한다** — 전역 `flutter`는 버전이 다를 수 있다.

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

## 버전

- **`pubspec.yaml`에는 버전 이름(`1.0.0`)만 둔다.** 버전 코드(`+N`)는 적지 않고
  빌드할 때 `--build-number`로 넘긴다. 번호를 올리려고 커밋하지 않는다.
- 버전 코드는 Play에 한 번 올리면 다시 쓸 수 없다. **올리기 전에 콘솔의 최신 번호를 보고** 그보다 크게 준다.
- 운영으로 낸 커밋에는 태그를 단다: `git tag v1.0.0+8 <커밋>`. 스토어에 있는 코드가 어느 커밋인지 이것으로 찾는다.

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
