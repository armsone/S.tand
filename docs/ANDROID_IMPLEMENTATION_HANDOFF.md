# S.tand iPhone → Android 완전 구현 인수인계

상태: Android 구현·검수의 최신 소스 기반 기준 문서

작성 기준: 2026-08-13, iOS `main` / `33711c009b7568779504a73685d616d6ec115db0`

Android 기존 확정 기준: iOS `0f664b2` / `1.0.0 (0.24.1)`

최신 앱 버전: `1.0.0 (0.25.1)` — `Configuration/Versions.xcconfig`의 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. `AppVersion.build`의 `0.24.2`는 Info.plist 조회 실패 때만 쓰는 fallback이며 정상 빌드 표시 기준이 아니다.

조사 범위: `0f664b2..33711c0`의 모든 커밋, 최신 앱 Swift, Xcode 프로젝트 설정, Widget, Share Extension, plist/entitlements/privacy manifest, `STandTests`, 현재 작업 트리. 아래 **최신 변경 원장**이 이후 0.24.1 기준 전수 원장과 충돌하면 아래 원장을 우선한다.

## 0. 최신 변경 원장 — 0f664b2 → 33711c0

### 0.1 누락 방지 기준과 실제 작업 트리

| 순서 | 커밋·빌드 | 실제 변경 | 최신 Android 판정 |
|---|---|---|---|
| 1 | `bf8c46b` · `0.24.2` | 최초 권한 설명, 카메라→마이크→위치 순차 요청, 3~7회 재안내, 자동 권한 팝업 제거 | **구현 필요** |
| 2 | `a68f474` · `0.24.3` | 별도 YouTube 설정·홈 패널·공식 WebKit 플레이어 시험 추가 | 이력만 기록, **구현 금지** |
| 3 | `769406c` · `0.24.4` | YouTube 모델·UI·설정 payload·테스트·프로젝트 참조를 전부 제거 | **최신 상태 유지** |
| 4 | `a97743a` · `0.25.0` | 전 화면 터치 목표·좁은 폭 대응·문구·설정 모드 선택·편집 경계·삭제 확인 개선 | **구현 필요** |
| 5 | `33711c0` · `0.25.1` | 매이트 진입 후 최초 60초 동안 화들짝 반응 억제 | **구현 필요** |

- `git log 0f664b2..33711c0`에서 위 5개가 전부 확인되며 빠진 커밋은 없다.
- 범위의 최종 net diff는 14개 경로, `839 insertions / 202 deletions`이다. 새 최종 파일은 `STand/UI/FirstLaunchPermissionView.swift` 하나이며 YouTube 두 파일은 생성 후 제거되어 최종 트리에 없다.
- 현재 작업 트리의 앱 관련 미커밋 차이는 `PROJECT_RULES.md`의 개발·검증 운영 규칙과 `STand.xcscheme`의 `parallelizable="YES"→"NO"`뿐이다. 둘 다 제품 동작/payload/UI 변경이 아니다. Android 문서 두 파일은 기존부터 미추적 상태였고 이번 갱신은 그 내용을 보존해 확장한다.
- 실제 빌드 설정은 `0.25.1`이나 현재 미커밋 `PROJECT_RULES.md`의 “현재 빌드 번호 0.24.4”는 뒤처져 있다. Android 표시·빌드 대응은 `Versions.xcconfig`의 `0.25.1`을 따른다.

### 0.2 최초 권한 안내와 앱 시작 게이트 (`bf8c46b`, 이후 `a97743a` 문구 정리)

#### 변경 전 → 후

| 항목 | `0f664b2` 이전 | `33711c0` 최종 | Swift 근거·테스트 | Android 구현 지침·검증 |
|---|---|---|---|---|
| 앱 최초 화면 | Root가 즉시 `appDidBecomeActive`와 `startNightSession` 실행 | 필요한 권한이 남고 스케줄상 표시 실행이면 z-index 200의 설명 화면이 정상 앱 시작을 막음 | `STandApp`, `RootView.startAppIfNeeded`, `FirstLaunchPermissionView`; `testFirstLaunchPermissionPromptShowsFirstThenEveryThreeToSevenLaunches` | Activity 프로세스 생성 때 1회만 평가. 설명이 뜬 동안 홈 gesture·편집·세션 시작 금지. 회전/Activity 재생성은 새 실행으로 세지 않도록 process-scoped coordinator/ViewModel 사용 |
| 설명 항목 | 사전 통합 설명 없음 | 3개 카드: `카메라와 플래시`, `마이크`, `위치 정보` | `FirstLaunchPermissionView.permissionRow` | Android는 플랫폼 권한 관계에 맞게 카메라/플래시를 한 카드로 설명하되 실제 torch 권한·카메라 권한 결합 여부는 Android API 기준으로 구현 |
| 권한 순서 | 날씨/마이크/카메라 기능 진입 때 각각 요청될 수 있음 | 한 번 누르면 아직 미결정인 **카메라 → 마이크 → 위치**만 차례로 요청. 거부해도 다음 단계와 앱 시작 계속 | `FirstLaunchPermissionCoordinator.requestNeededPermissions`, `requestCameraIfNeeded`, `requestMicrophoneIfNeeded`, `requestLocationIfNeeded` | 각 callback/Activity Result 완료 뒤 다음 요청. denied/don't-ask-again도 중단 금지. 이미 granted/denied인 항목은 OS dialog 재호출 금지 |
| 재안내 | 없음 | 누락 첫 확인은 즉시 표시. 이후 안내 직후 `Int.random(in: 3...7)` 저장; 안내하지 않는 각 **프로세스 앱 실행**마다 1 감소, 1 이하인 다음 평가에서 표시 | `FirstLaunchPermissionPromptPolicy`, UserDefaults keys `firstLaunchPermissionPromptHasShownV1`, `firstLaunchPermissionPromptLaunchesRemainingV1`; 위 테스트 | 기기 로컬 저장. 첫 안내 뒤 선택된 N이 3이면 다음 두 실행 skip, 세 번째 재표시가 되도록 iOS 정책을 그대로 fixture test. 모든 권한 허용 시 두 key 삭제 |
| 앱 재진입 | scene active마다 수명주기 재호출 | `@StateObject` coordinator는 process당 1개. `hasStartedApp`으로 최초 시작과 foreground 복귀 분리; inactive/background는 시작 전 model resign 호출 금지 | `STandApp.body`, `RootView.onAppear/onChange(scenePhase)/startAppIfNeeded` | 회전, configuration change, 동일 process foreground 복귀로 카운터가 감소하거나 설명이 중복되지 않는 UI test 필요 |
| 자동 마이크 요청 | 매이트 자동 시작에서 권한을 요청할 수 있음 | 자동 경로는 `audio.startIfAuthorized()`만 호출 | `StandViewModel.syncSleepCareMonitoring` | 자동 시작은 OS 마이크 prompt 금지. 설정 복구 또는 통합 설명 버튼만 명시 요청 |
| 자동 위치 요청 | `refreshIfNeeded`가 `.notDetermined`면 바로 request | 기본 `requestPermission=false`; 미결정이면 `locationDenied` 상태만 표시. 설정에서 위치를 켤 때만 `requestPermission: true` | `WeatherService.refreshIfNeeded/setLocationEnabled`, `StandViewModel.setLocationPermissionEnabled` | 앱 시작/단순 refresh에서 위치 dialog 금지. 설정의 명시 enable은 요청 허용 |

#### 최종 화면 원문·시각 규격

- 배경: black → RGB `(0.12, 0.075, 0.055)` 세로 LinearGradient, safe area 무시.
- Scroll content 최대 폭 560, 가로 padding 22, 세로 padding 30, 주 VStack 간격 22.
- 상단 SF Symbol `checkmark.shield.fill`, 42pt semibold, 현재 theme accent. 제목 `시작하기 전에` title2 bold, 설명 `S.tand가 필요한 이유를 먼저 알려드릴게요.` subheadline medium / white 60%.
- 카드 간격 10, 행 padding 14, corner radius 16, fill white 7%, stroke white 9% / 1pt. 아이콘 18pt semibold, 36×36, accent 13%, corner radius 10. 제목 subheadline bold, 본문 footnote medium / white 72%.
- 카드 1: SF Symbol `camera.fill`; `카메라와 플래시`; `방 밝기를 확인하고, 어두울 때 화들짝 모드에서만 잠깐 밝힙니다. 사진·영상은 저장하거나 전송하지 않습니다.`
- 카드 2: `mic.fill`; `마이크`; `잠꼬대·코골이를 감지하고 필요한 소리만 이 기기에 저장합니다.`
- 카드 3: `location.fill`; `위치 정보`; `현재 날씨에만 사용하며 가능한 최소 정확도와 필요한 범위만 요청합니다.`
- 보조 문구: `허용하지 않아도 앱은 시작됩니다. 허용한 기능만 작동합니다.` footnote semibold / white 58%.
- 버튼: `권한 확인하고 시작`, 진행 중 spinner와 `권한 확인 중…`; 최소 높이 52, corner radius 16, accent 배경. 진행 중 disabled. 접근성 hint `결정하지 않은 권한만 차례로 확인한 뒤 앱을 시작합니다`.
- iOS OS 문구: 카메라 `화들짝 모드의 후면 플래시와 방 밝기 측정에 카메라 접근을 사용합니다. 사진이나 영상은 저장하거나 전송하지 않습니다.`; 마이크 `잠꼬대·코골이 후보를 감지하고 필요한 소리만 이 기기에 저장하려면 마이크 접근이 필요합니다.`; 위치 `현재 날씨를 표시하기 위해 앱을 사용하는 동안 위치를 요청하며, 가능한 최소 정확도로 사용합니다.` (`Info.plist`). Android Manifest/사전 설명은 같은 데이터 사용 목적을 유지하되 Android permission 명칭과 coarse location 정책으로 번역한다.
- iOS는 torch 별도 권한이 없고 video camera authorization을 공유한다. Android는 `CAMERA`, microphone, coarse location의 현재 API/기기 정책을 각각 따르며 iOS의 권한 API를 문자 그대로 모방하지 않는다.

#### 권한 검증 절차

1. 신규 설치: 설명 화면이 OS dialog보다 먼저 한 번 보이고 홈 gesture가 반응하지 않는지 확인.
2. 카메라 deny → 마이크 allow → 위치 deny: 세 dialog 순서, 거부 후 계속 진행, 홈 진입, 허용 기능만 작동 확인.
3. 이미 결정된 권한 혼합: 결정된 항목을 건너뛰고 미결정 항목만 순차 요청하는지 확인.
4. 첫 안내 후 저장 interval을 3과 7로 고정한 fixture: 각각 정확한 process launch 간격 확인. 회전·scene/Activity 재진입은 값 불변 확인.
5. 모든 권한 허용 후 재실행: 설명 미표시와 두 로컬 key 삭제 확인.
6. 설정의 기존 권한 복구 flow, 저장된 `appSettings`, 라디오·녹음 파일이 유지되는지 회귀 확인.

### 0.3 폐기된 YouTube 실험 (`a68f474` → `769406c`)

| 단계 | 추가/제거 내용 | 근거 | Android 지침 |
|---|---|---|---|
| 0.24.3 추가 | `YouTubeConfiguration`(HTTPS, youtube.com/youtu.be, video 11자, playlist 10...128자, 이름 30, URL 2048), 설정 카드, 홈 144×패널, 0.8초 long press 편집, 비영속 WebKit 공식 embed player, 앱 이탈 시 닫기, 재생 중 radio/mic suspension | `a68f474`; 당시 `YouTubeConfiguration.swift`, `YouTubePlayerView.swift`, `RootView`, `SettingsView`; 당시 테스트 3개 | 이력·마이그레이션 위험 확인용으로만 보존 |
| 0.24.4 제거 | 위 모델·뷰·project reference·AppSettings의 `youtube` 및 layout transform·UI·테스트를 대칭 제거 | `769406c` | **YouTube 카드, 홈 패널, WebView/player, 저장 필드, 권한, 링크를 구현하지 않는다.** 최종 제품은 라디오 최대 2채널만 유지 |

- 제거 이유는 `PROJECT_RULES.md` 빌드 이력의 “영상별 외부 재생 제한으로 제거 결정”이다. 최신 코드에 남은 YouTube symbol/string/reference는 없다.
- 0.24.3 payload를 실제로 저장한 사용자가 있을 수 있으므로 Android가 iOS JSON을 가져오는 경로가 있다면 unknown `youtube`와 layout `youtube` key를 안전하게 무시해야 한다. 이를 라디오로 자동 변환하거나 다시 노출하지 않는다. 최신 iOS decoder는 CodingKeys에서 필드가 제거되어 unknown key를 무시하고, 다음 정상 저장 때 제거된 필드는 다시 encode하지 않는다.
- 검증: 소스/project 전역에서 `YouTubeConfiguration`, `YouTubePlayerView`, `youtube` product UI 참조가 0인지 확인하고, 설정·홈·편집에 라디오 2채널만 보이는지 UI test한다.

### 0.4 전 화면 사용성과 접근성 (`a97743a`, 0.25.0)

| 영역 | 변경 전 → 후 | 최신 수치·문구 | 근거 | Android 구현·검증 |
|---|---|---|---|---|
| 최초 권한 | 플래시/카메라 2행 + 별도 iPhone 설명 → `카메라와 플래시` 1행 | 아이콘 32→36, 본문 white 62%→72%; 총 3행 | `FirstLaunchPermissionView` | 위 0.2 원문으로 screenshot/TalkBack 확인 |
| 홈 숨김 제어 안내 | opacity 18%, lamp 상태별 `탭하면…` + moon/lightbulb → opacity 62%, `탭하여 녹음·설정 열기` + `ellipsis.circle.fill` | caption semibold / white 62%; 접근성 hint에서 잘못된 `두 번` 삭제 | `RootView.inactiveStartView/bottomControls/controlSilhouette` | 실제 activate가 단일 접근성 동작인지 확인. 희미한 상태에서도 대비와 44dp target 검증 |
| 화면 편집 | 패널이 canvas/chrome 밖으로 이동 가능 → 안전영역·상단 editor toolbar·하단 controls/글꼴 palette 안쪽으로 중심 clamp | rendered size는 각 축 `max(44, panelSize×scale)`; portrait leading/trailing 14, landscape 24; top outer 18/14, top clearance 12/2; bottom clearance 6/2; palette 190/126 + bottom 22/14 + clearance 8/2 | `PanelEditingPolicy.protectedInsets/editingRegion/clampedCenter`, `EditablePanel.clampTransformToEditingArea`; 기존 `testPanelEditingRegion…`, `testPanelCenterClamps…` | drag, pinch 종료, top-left resize 종료, appear, inset 변화마다 clamp. 30...200% scale와 10% center snap은 유지. font palette/rotation/큰 글꼴에서 panel이 chrome 밑으로 숨지 않는지 검증 |
| 설정 순서 | Hero → radio → 2열 cards → Hero → 2열 cards → radio full width | width `<720`: 1열, `≥720`: 2열; horizontal padding 14/24, grid spacing 14 | `SettingsView.body` | radio card는 grid 밖 마지막 full-width. 좁은 폰/태블릿 모두 확인 |
| 설정 Hero | 상태 pill tap으로 2초 mode toggle → pill은 읽기 전용, 아래 segmented picker로 유지 방식 직접 선택 | Picker label `화면 모드 유지`; 값은 `자동`, `오브제 유지`, `매이트 유지`; minHeight 44; hint `자동 전환 또는 오브제와 매이트 모드 유지를 선택합니다` | `SettingsHero`, `StandModePreference.title`, `StandViewModel.setModePreference` | 비활성 session에서는 disabled. 선택 저장/재실행 및 실제 mode 적용 확인. pill tap 전환 구현 금지 |
| 테마 | 고정 HStack 4개, 이름 9.5pt → adaptive grid | 최소 column 72, spacing 10, caption semibold | `ThemePalettePicker` | Dynamic Type에서 겹침 없이 wrap |
| 폰트 | 항상 3열, caption2 → 접근성 크기 1열/그 외 3열, caption | spacing 8 | `ClockFontSelectionView`, `ClockFontGridTile` | Dynamic Type accessibility size에서 1열 확인 |
| 설정 radio inline | play icon 34→44×48, 편집 34→48, 이름 1→2줄, 닫기 ≥44, browser 40→48, trash 42→48, save 42→48 | 모든 주요 target 44pt 이상 | `inlineRadioChannelRow/inlineRadioEditor` | 긴 이름·큰 글꼴·TalkBack target 확인 |
| 채널 관리 삭제 | swipe/context 즉시 삭제 → 동일 confirmation | title `N을 삭제할까요?`, destructive `채널 삭제`, cancel `취소`, message `삭제한 채널 주소는 되돌릴 수 없습니다.` | `InternetRadioChannelManagementView.pendingDeletion/confirmationDialog` | swipe/context 모두 confirm 전 데이터 불변, 취소 보존, confirm 후 재생/홈 상태 정리 확인 |
| 채널 접근성 | 실제로 없는 “두 번 탭하여 홈 선택” hint → 현재 동작 설명 | selected `현재 홈에 표시되는 채널입니다`; other `편집에서 순서를 바꾸면 홈에 표시할 수 있습니다`; pencil 32→48 | `channelRow` | 오해 유발 action을 추가하지 말고 순서 기반 홈 선택 유지 |
| 브라우저 toolbar | 단일 HStack, 동적 back/close만 → `ViewThatFits`: 넓으면 한 줄, 좁으면 주소행+보조행; 항상 별도 X close 제공 | spacing 7, 기존 controls 44; 주소 min width 88; 보조행 reload/star/X; favorite/error X target 44 | `InternetRadioBrowserView.addressBar/browserAddressField/browserReloadButton/browserCloseButton` | back은 popup→history→dismiss 의미 유지, 별도 X는 항상 즉시 browser dismiss. 큰 글꼴/좁은 폭에서 2행 fallback과 WebView 가림 확인 |
| 녹음 선택 dock | 38pt 단일행 → `ViewThatFits` 단일행/2행 fallback | clear/delete 48×48, merge minHeight 48, spacing 10/8 | `RecordingSelectionDock` | 좁은 폭·큰 글꼴에서 버튼 잘림/겹침 없이 동작 |
| 녹음 row | checkbox 40×44, play 42, menu 42×44 → 모두 48×48 | merged indicator도 48 | `RecordingRow` | row 본문 play와 checkbox/menu gesture 충돌 확인 |
| 재생 dock | 38pt 중심의 고정 HStack → `ViewThatFits` 한 줄/두 줄 fallback | play/boost/X 48; slider minWidth 120; 시간 caption white 62%; boost inactive white 64% | `PlaybackProgressBar` | 좁은 폭, 긴 시간, Dynamic Type에서 seek·pause·boost·close 검증 |

### 0.5 매이트 진입 후 화들짝 지연 (`33711c0`, 0.25.1)

- 변경 전: 매이트 모드 진입 직후 소리/움직임 callback이 `wakeForSleepMovement`를 호출하면 즉시 화들짝 화면·event·조건부 torch가 시작될 수 있었다.
- 변경 후: `StartleActivationPolicy.delay = 60`. `mateModeEnteredAt`이 없거나 `now - enteredAt < 60`이면 `wakeForSleepMovement`가 **아무 동작 없이 return**한다. 정확히 60초부터 허용한다.
- timestamp는 wall clock이 아니라 `ProcessInfo.processInfo.systemUptime`을 사용한다. `applyEnvironmentDisplayMode`에서 mode가 실제로 바뀔 때 sleeping이면 기록하고 stand이면 nil로 지운다. 같은 sleeping 값을 재적용할 때는 타이머를 재시작하지 않는다.
- 첫 60초 동안 억제되는 범위는 화들짝 event 생성, lamp wake, torch wake다. 매이트의 마이크 학습·후보 감지·녹음 세션 자체를 60초 중단하는 정책은 아니다.
- 근거: `StartleActivationPolicy`, `StandViewModel.mateModeEnteredAt`, `wakeForSleepMovement`, `applyEnvironmentDisplayMode`; `testStartleActivationWaitsForFullMinuteAfterEnteringMateMode`가 nil/59.999 false, 60 true를 검증한다.
- Android: `SystemClock.elapsedRealtime()` 같은 monotonic clock을 사용한다. Object→Mate, 강제 Mate, 재진입 경로를 모두 한 transition 함수로 모으고, Mate→Object에서 timestamp clear. process death 후 임의로 과거 시간을 복원하지 말고 새 runtime transition 기준으로 안전하게 다시 60초를 센다.
- 검증: 0초·59.999초 event 무반응, 60.000초 event 반응; Mate 값을 중복 set해 deadline이 늘어나지 않음; Object 왕복 시 새 60초; 억제 중 녹음 감지 pipeline은 정상; dark/fresh camera 조건이 없으면 60초 이후에도 torch는 켜지지 않음.

### 0.6 변경이 없음을 확인한 영역

`0f664b2..33711c0`의 net diff와 최신 소스를 대조했을 때 다음 핵심 정책은 위 변경 외에는 그대로다: 라디오 URL validation·최대 2채널·재연결/volume, 오디오 분류 threshold와 writer/recording manifest, 날씨 API·3km desired accuracy·30분 cache(단 자동 권한 요청만 변경), camera 밝기 threshold/주기, motion threshold, face-down, torch의 dark/fresh 조건, Share Extension, Widget, entitlements, Privacy Manifest. Android는 아래 0.24.1 전수 원장을 계속 적용하되, 이 0절의 override를 반드시 반영한다.

## A. 0.24.1 전수 원장의 판정 규칙과 조사 한계

- 이 문서는 실제 코드가 최우선이다. `PROJECT_RULES.md` 및 기존 `docs/ANDROID_IMPLEMENTATION_HANDOFF.md`와 코드가 다르면 아래 **충돌** 표에 기록하고 실제 Swift 동작을 명세로 삼았다.
- `Swift 근거`는 `파일:줄`과 타입·함수명을 함께 적었다. 줄 번호는 위 기준 커밋에서만 안정적이다.
- `테스트 근거`가 `없음`이면 XCTest가 그 UI/통합 동작을 직접 검증하지 않는다는 뜻이다. 정책 테스트가 있어도 SwiftUI 렌더링·히트 영역·애니메이션·햅틱을 검증한 것으로 간주하지 않는다.
- 소스와 XCTest는 전수 검색했지만 이 문서 작업에서 iPhone/iPad 실기기, VoiceOver, 카메라, 마이크, 플래시, 실제 라디오 스트림, WebView 사이트, 네트워크 실패, TestFlight 바이너리를 직접 실행하지 않았다. 따라서 해당 항목은 **소스 확인**, **실기기 미확인**으로 구분한다.
- 저장 여부 표기: `예`는 영속 저장, `아니오`는 현재 프로세스/UI 상태, `파일`은 녹음·manifest, `OS`는 OS 권한/클립보드/공유 UI이다.

### 0.1 실제 조사 대상

| 영역 | 실제 파일 |
|---|---|
| 앱 시작·방향·scene | `STand/App/STandApp.swift:1-69` |
| 홈·패널·편집·플립 UI | `STand/UI/RootView.swift:1-3499` |
| 설정·권한·폰트·라디오 관리 | `STand/UI/SettingsView.swift:1-2001` |
| 수면 소리 UI | `STand/UI/RecordingsView.swift:1-1179` |
| 내장 브라우저 | `STand/UI/InternetRadioBrowserView.swift:1-1083` |
| 상태·모드·수명주기·카메라·플래시 | `STand/UI/StandViewModel.swift:1-1699` |
| 설정·기본값·마이그레이션 | `STand/Models/AppSettings.swift:1-880` |
| 라디오 모델·공유 초안 | `STand/Models/InternetRadioConfiguration.swift:1-153` |
| 라디오 재생 | `STand/Services/InternetRadioPlayer.swift:1-367` |
| 녹음 감지·writer | `STand/Audio/AudioAnalysis.swift:1-381`, `STand/Audio/AudioCaptureService.swift:1-779` |
| 녹음 저장·세션·재생 | `STand/Services/RecordingLibrary.swift:1-913` |
| 날씨·위치 | `STand/Services/WeatherService.swift:1-294` |
| 움직임·뒤집기 | `STand/Services/WakeMotionMonitor.swift:1-131` |
| 공유 확장 | `STandRadioShare/ShareViewController.swift:1-193`, `STandRadioShare/Info.plist:1-39` |
| 공유 확장 권한·개인정보 | `STandRadioShare/STandRadioShare.entitlements:1-10`, `STandRadioShare/PrivacyInfo.xcprivacy:1-23` |
| 잠금화면 위젯 | `STandWidget/STandWidget.swift:1-70`, `STandWidget/Info.plist:1-29` |
| 권한·개인정보 | `STand/Resources/Info.plist:1-83`, `STand/Resources/STand.entitlements:1-10`, `STand/Resources/PrivacyInfo.xcprivacy:1-40` |
| 자동 테스트 | `STandTests/AudioAnalysisTests.swift:1-3295` — XCTest 130개, `XCTAssert*` 호출 541개, XCUITest/스냅샷 테스트 없음 |

## 1. 전체 화면·팝업·진입/종료 지도

| ID | 화면/오버레이 | 진입 | 종료/복귀 | Swift 근거 |
|---|---|---|---|---|
| H0 | 홈(앱 시작 시 자동 돌봄 시작) | 앱 실행, `stand://open`, foreground 복귀 | 앱 background/inactive; 별도 홈 종료 버튼 없음 | `STandApp.body` `STand/App/STandApp.swift:50-68`; `RootView.body/onAppear` `RootView.swift:303-515` |
| H1 | 돌봄 중지 상태의 시작 화면 | 저전력 보호 등으로 `isNightSessionActive == false` | `S.tand 시작` 탭 | `RootView.centerContent` `RootView.swift:566-595`; `StandViewModel.startNightSession` `StandViewModel.swift:516-547` |
| H2 | 앱 밝기 HUD | 홈 전체 화면 세로 우세 드래그 | 손을 떼면 즉시 사라짐 | `screenAdjustmentGesture/adjustmentHUD` `RootView.swift:667-716`; `AppBrightnessHUD` `RootView.swift:1046-1073` |
| H3 | 라디오 볼륨 HUD | 홈 전체 화면 가로 우세 드래그 | 손을 떼면 즉시 사라짐 | `screenAdjustmentGesture/adjustmentHUD` `RootView.swift:667-716`; `RadioVolumeHUD` `RootView.swift:1075-1102` |
| H4 | 시계 크기 HUD | 홈 두 손가락 pinch | 종료 1.2초 후 0.25초 fade | `clockMagnificationGesture/scheduleClockScaleFeedbackHide` `RootView.swift:799-852`; `ClockScaleFeedbackView` `RootView.swift:1104-1123` |
| H5 | 화면 전체 암전 | 활성 돌봄 중 기기 face-down | 다시 들면 복귀 | `RootView.body` `RootView.swift:413-419`; `applyFaceDownState` `StandViewModel.swift:1221-1236` |
| E0 | 세로/가로 패널 편집 | 홈 전체 0.8초 long press | `저장`; 앱 inactive/background에서는 transient reset만 하며 편집 상태 자체는 코드상 명시 종료하지 않음 | `screenPressGesture/enterScreenEditing` `RootView.swift:718-740,651-665`; `ScreenEditorView` `RootView.swift:2148-2528` |
| E1 | 편집 하단 글꼴 팔레트 | 편집 중 시계 패널 탭 | 시계 재탭 또는 편집 저장 | `ScreenEditorView.body/fontPalette` `RootView.swift:2163-2285,2508-2527` |
| R0 | 홈 라디오 채널 sheet | 홈 라디오 패널 0.8초 long press; 편집 중 라디오 패널 탭; Safari 공유 초안 활성화 | `취소`/`저장`; 공유 초안은 interactive dismiss 금지 | `InternetRadioPanel` `RootView.swift:1408-1580`; `RootView.sheet` `RootView.swift:450-490`; `InternetRadioConfigurationView` `RootView.swift:2530-2696` |
| R1 | 인터넷 라디오 채널 관리 sheet | 편집의 빈 두 번째 라디오 패널 탭 | `완료` 또는 sheet dismiss | `editableRadioPanels` `RootView.swift:2331-2352`; `InternetRadioChannelManagementView` `SettingsView.swift:1547-1810` |
| R2 | 채널 추가/수정 push 화면 | R1의 첫 채널/추가/연필/context menu/swipe action | 저장 성공 시 pop; navigation back은 초안 폐기 | `InternetRadioChannelEditorView` `SettingsView.swift:1813-1957` |
| B0 | 전체 화면 내장 브라우저 | 설정 라디오 inline, R0, R1, R2의 `웹에서 찾기/주소 찾기` | 뒤로 기록 없음/팝업 닫기/0.5초 long press 닫기 | `InternetRadioBrowserView` `InternetRadioBrowserView.swift:8-410` |
| B1 | 즐겨찾기 panel | B0 상단 별 버튼 | 별 재탭, X, 항목 선택, 주소 제출 | `favoritesPanel` `InternetRadioBrowserView.swift:181-203,306-373` |
| B2 | 브라우저 오류 panel | 잘못된 주소/클립보드 없음/탐색 거부/로드 실패/process 종료 | X 또는 다음 정상 탐색 | `browserMessagePanel` `InternetRadioBrowserView.swift:375-401`; session 오류 `723-865` |
| S0 | 설정 sheet | 홈 하단 `설정 열기` | `완료` 또는 sheet dismiss | `RootView.bottomControl` `RootView.swift:941-948`; `SettingsView` `SettingsView.swift:7-143` |
| S1 | 설정 인터넷 라디오 inline 편집 | S0 `첫 채널 추가/채널 추가/연필` | `닫기`, 저장 성공, S0 종료 | `inlineRadioEditor` `SettingsView.swift:294-544` |
| S2 | 시계 글꼴 선택 | S0 `시계 글꼴` | navigation back | `ClockFontSelectionView` `SettingsView.swift:1354-1387` |
| S3 | 폰트 저작권 목록 | S0 `내장 폰트 저작권` | navigation back | `ClockFontLicensesView` `SettingsView.swift:1455-1488` |
| S4 | 폰트 라이선스 전문 | S3 글꼴 행 | navigation back | `FontLicenseDetailView` `SettingsView.swift:1490-1523` |
| A0 | 라디오 채널 삭제 confirmation | S0 inline trash, R0/R2 삭제 | 삭제/취소 | `SettingsView.body` `SettingsView.swift:105-125`; `InternetRadioConfigurationView` `RootView.swift:2654-2666`; `InternetRadioChannelEditorView` `SettingsView.swift:1922-1936` |
| A1 | 추천 설정 복원 confirmation | S0 `추천 설정 복원` | 복원/취소 | `SettingsView.body/informationCard` `SettingsView.swift:126-137,546-601` |
| P0 | 수면 소리 sheet | 홈 `녹음 목록 보기`; S0 `수면 소리 열기/녹음 N개 보기` | `닫기`/sheet dismiss | `RootView.bottomControl` `RootView.swift:930-939`; `SettingsView.detectionCard` `SettingsView.swift:279-286`; `RecordingsView` `RecordingsView.swift:3-227` |
| P1 | 선택 dock | P0에서 원본 하나 이상 선택 | `선택 해제`, 작업 완료, 화면 종료 | `RecordingsView.safeAreaInset` `RecordingsView.swift:86-104`; `RecordingSelectionDock` `RecordingsView.swift:658-711` |
| P2 | 재생 dock | P0에서 녹음 재생 | X, 화면 종료, 다른 녹음 | `PlaybackProgressBar` `RecordingsView.swift:1048-1120` |
| A2 | 녹음 전체/선택/합본 후 원본/단일 삭제 confirmation | P0 각 메뉴·삭제 버튼 | 확정/취소 | `RecordingsView.body` `RecordingsView.swift:148-209` |
| A3 | 녹음 작업 실패 alert | merge/delete 오류 | `확인` | `RecordingsView.body` `RecordingsView.swift:210-220` |
| X0 | iOS 공유 확장 | Safari Share sheet의 Web URL 1개 | `라디오 주소로 가져오기` 성공 0.45초 후 완료; `취소` | `ShareViewController` `STandRadioShare/ShareViewController.swift:4-183`; activation `STandRadioShare/Info.plist:23-37` |
| W0 | 잠금화면 accessory circular widget | 위젯 갤러리/잠금화면 | 탭 시 `stand://open` | `STandLaunchWidgetView/STandLaunchWidget` `STandWidget.swift:22-62` |

## 2. 화면별 완전 입력 표

요청된 열 형식을 그대로 사용한다. VoiceOver의 “두 번 탭”은 버튼 활성화 방식이고, 일반 터치의 앱 정의 `TapGesture(count: 2)`와 구분한다.

### 2.1 홈·시작·오버레이

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| H0 홈 | 편집/시트가 없는 홈 `RootView` 전체 content shape | 위/아래 drag, 최소 10pt 후 최초 우세 축 고정 | `!isEditingScreen && presentedSheet == nil`; 세로 이동 절댓값이 가로보다 큼 | 시작 앱 밝기에서 `-translationY/(viewportHeight×0.5)`를 더해 0...1 clamp; 앱 내 lamp만 갱신, 시스템 밝기 쓰지 않음; 중앙 `앱 밝기 N%` | 배경 intensity 0.08초 linear; HUD는 drag 중만; 끝단 100%를 1초 유지하면 medium impact와 오브제 고정 | 예: `lampIntensity`, `modePreference` | `screenAdjustmentGesture`, `initialAdjustmentState` `RootView.swift:667-706`; `SimplifiedBrightnessModePolicy` `StandViewModel.swift:63-120`; update `1238-1334` | `testHalfScreenVerticalDragCoversTheFullSystemBrightnessRange` `AudioAnalysisTests.swift:1881-1910`; `testSystemBrightnessCannotOverwrite...` `1911-1929`; 경로 UI 테스트 없음 |
| H0 홈 | 같은 전체 영역 | 좌/우 drag, 최소 10pt 후 최초 우세 축 고정 | 편집/시트 없음; 가로 절댓값이 세로 이상; 라디오 재생 여부와 무관 | 시작 플레이어 volume에서 `translationX/(viewportWidth×0.5)`를 더해 0...1 clamp; 오른쪽 증가, 왼쪽 감소; AVPlayer volume만 변경, 시스템/녹음 volume 불변; 중앙 `라디오 볼륨 N%` | HUD drag 중; 별도 햅틱 없음 | 아니오: 프로세스의 `InternetRadioPlayer.volume`; stop/새 연결/재연결에는 유지, 앱 재실행에는 1.0 | `RootView.swift:667-716`; `RadioVolumePolicy`, `updateVolume`, player 적용 `InternetRadioPlayer.swift:35-49,53-56,103-132` | `testHorizontalDragCoversFullRadioVolumeRangeAndClamps` `AudioAnalysisTests.swift:382-417`; UI/재실행 테스트 없음 |
| H0 홈 | 전체 영역, child 라디오 high-priority 입력 제외 | 단일 탭 | 편집 아님, 돌봄 활성 | 현재 환경 모드 stand면 목표 0.35, sleeping이면 0.8; 40×50ms=2초 선형 보간 후 `modePreference=.automatic` | 종료 시 light impact; 매 step 앱 배경 반영 | 예: 최종 lamp intensity와 automatic | `screenPressGesture/handleScreenTap` `RootView.swift:718-755`; `toggleObjectMateMode` `StandViewModel.swift:1294-1319` | `testSimplifiedBrightnessModeBoundariesAndTapTargets` `1772-1807`; 실제 2초 UI/gesture 없음 |
| H0 홈 | 전체 영역 | 더블 탭 | 편집 아님 | `오렌지→그레이→미드나이트→세이지→오렌지` 순환 | 0.28초 easeInOut, light impact | 예: `displayTheme` | `screenPressGesture/toggleDisplayTheme` `RootView.swift:718-749`; enum toggle `AppSettings.swift:97-126` | `testDisplayThemeRoundTripsAndLegacySettingsUseColor` `AudioAnalysisTests.swift:1150-1165`; gesture 없음 |
| H0 홈 | 전체 영역 | 0.8초 long press, 최대 이동 12pt | 편집/시트 없음 | 현재 orientation의 layout 사본으로 E0 진입, controls reveal | 진입 0.25초 easeOut + medium impact | 초안만; 저장 전 아니오 | `screenPressGesture/enterScreenEditing` `RootView.swift:718-729,651-656` | 정책 테스트만 `testPanelEditorResetPreservesBottomButtonOrder` `917-932`; gesture 없음 |
| H0 홈 | 전체 영역 | 두 손가락 pinch | 편집 아님 | 최초 scale×magnification을 0.7...1.35 clamp, 시계 global scale 변경, `시계 크기 N%` | change HUD 0.12초 easeOut; 종료 1.2초 대기 후 0.25초 fade; 햅틱 없음 | 예: `clockScale` | `clockMagnificationGesture` `RootView.swift:799-823`; `ClockScaleFeedbackView` `1104-1123` | clamp 직접 UI 테스트 없음 |
| H0 홈 | 투명 1×1 접근성 요소 `홈 화면 제어` | VoiceOver adjustable increment/decrement | 돌봄 활성일 때만 요소 존재 | 앱 밝기 ±0.1 clamp | selection haptic | 예 | `homeAccessibilityControls` `RootView.swift:757-792` | 없음 |
| H0 홈 | 같은 접근성 요소 custom actions | `오브제와 매이트 전환`, `테마 전환`, `화면 편집 열기`, `시계 크게/작게` | 돌봄 활성; 각 함수 guard 적용 | 각각 일반 탭/더블탭/long press/pinch의 의미 실행; 시계 ±0.1 clamp | 테마 light, 밝기/시계 selection; 편집 접근성 경로에는 코드상 medium impact 없음 | 항목별 예 | `RootView.swift:773-797` | 없음 |
| H0 홈 | 라디오 단일 패널의 전체 패널 | 탭 | panel child interaction 허용, 저장 channel 존재 | inactive면 해당 channel 연결; 같은 active면 stop; 다른 active면 switch | 표면/button 자체 애니메이션·햅틱 없음 | 아니오 | `DashboardCanvas` callback `RootView.swift:629-636`; `InternetRadioPanel.body` `1408-1580`; `toggleInternetRadioPlayback` `StandViewModel.swift:826-837` | mutation 정책 `AudioAnalysisTests.swift:460-528`; UI 없음 |
| H0 홈 | 라디오 단일 패널 전체 | 0.8초 long press, 최대 이동 12pt | panel child interaction 허용 | 해당 channel R0 편집 sheet | medium impact | 초안만 | `InternetRadioPanel.body` `RootView.swift:1444-1459` | 없음 |
| H0 홈 | 묶인 두 라디오의 각 반쪽 | 탭/0.8초 long press | `radiosGrouped && 2 channels` | 해당 반쪽 channel 재생/편집 | long press medium | 재생 아니오/편집 저장 시 예 | `InternetRadioGroupedPanel` `RootView.swift:1581-1653` | merge 정책 `AudioAnalysisTests.swift:432-459`; interaction UI 없음 |
| H0 홈 | 하단 숨김 상태의 전체 80pt 높이 reveal target | 버튼 활성화 | `isNightSessionActive && !controlsVisible`; 현재 코드에서 `scheduleControlsHide`가 즉시 visible로만 설정해 일반 경로로는 거의 도달하지 않는 상태 | controls reveal | light impact | 아니오 | `bottomControls` `RootView.swift:856-871`; metrics `100-115`; `scheduleControlsHide` `StandViewModel.swift:1409-1413` | `testHiddenControlRevealTargetIsTwice...` `AudioAnalysisTests.swift:1541-1548` |
| H0 홈 | 하단 `녹음 목록 보기` tile | 탭 | 돌봄/controls 표시; 항상 enabled | 마이크 감시 일시중지, 라디오 stop, P0 sheet | 없음 | suspension 아니오 | `bottomControl(.recordings)` `RootView.swift:930-939`; `pauseMonitoringForPlayback` `StandViewModel.swift:813-824` | 없음 |
| H0 홈 | 하단 `설정 열기` tile | 탭 | controls 표시 | S0 sheet | 없음 | 아니오 | `RootView.swift:941-948` | 없음 |
| H1 시작 | 중앙 `S.tand 시작` | 탭 | `isNightSessionActive == false`; 배터리 비충전 20% 초과 또는 충전/unknown | 돌봄 시작, idle timer 금지, posture/weather/필요 감시 시작, 앱 brightness를 system brightness에서 초기화 | borderedProminent orange; 별도 햅틱 없음 | 시작 시 mode/brightness/threshold/auto dim 값을 덮어써 저장 | `RootView.swift:566-595`; `startNightSession` `StandViewModel.swift:516-547` | battery policy `AudioAnalysisTests.swift:2134-2148`; 통합 UI 없음 |
| H1 시작 | 같은 버튼 | 탭 | 비충전 battery ≤20% | 시작하지 않고 보호 banner 유지, idle timer 허용 | 없음 | 아니오 | `StandViewModel.swift:518-524` | `testBatteryProtectionOnlyStopsWhenLowAndUnplugged` `2134-2148` |
| H0/H1 | 기기 전체 | face-down / 다시 들기 | face-down 진입은 돌봄 활성; hysteresis gravityZ 0.82 enter/0.62 exit | black overlay와 app lamp 0; 다시 들면 저장 앱 밝기·자동 모드 복구; system brightness 불변 | overlay `.opacity` transition; 햅틱 없음 | 아니오 | `RootView.swift:413-419`; `DevicePosturePolicy` `WakeMotionMonitor.swift:16-83`; `applyFaceDownState` `StandViewModel.swift:1221-1236` | `testFaceDownPostureUsesHysteresis...` `AudioAnalysisTests.swift:2188-2195`; 실기기 없음 |
| H0 | 상단/상태/중앙/footer | 입력 없음 | 표시 상태에 따라 | 좌 mode label, 중앙 logo, 우 battery; 중앙 panels; footer `0.25.1 · 밝기 N%`; battery protection/recording error banner | controls opacity 0.3초; banner top+opacity; 테마 0.28초 | 아니오 | `RootView.body/topBar/statusBanners`, `Versions.xcconfig` | typography/layout 정책 일부; UI 표시 직접 검증 필요 |

### 2.2 홈 패널 편집

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| E0 편집 | 각 패널의 최소 44×44 투명 hit area/패널 본체 | drag, 최소 2pt | 편집 중 | 시작 위치 + translation/canvas로 정규화하여 x/y 이동; 렌더 크기를 포함해 safe area·상단 editor toolbar·하단 controls/글꼴 palette 내부로 중심 clamp; 중심선에 panel 길이의 가운데 10%가 닿으면 해당 축 0으로 snap | snap 축 최초 진입마다 selection haptic | 초안; `저장` 전 아니오 | `EditablePanel.body/clampTransformToEditingArea`; `PanelEditingPolicy.editingRegion/clampedCenter/shouldSnapToCenter` | `testPanelEditingRegion…`, `testPanelCenterClamps…`, `testPanelCenterSnaps...`; 실제 drag/rotation UI 필요 |
| E0 편집 | 각 패널 | pinch | 편집 중 | 시작 scale×magnification, 0.3...2.0 clamp | 없음 | 초안 | `EditablePanel` `RootView.swift:2990-3004`; scale constants `PanelEditingPolicy` `2697-2864` | `testRadioPanelUsesTheSameThirtyToTwoHundredPercentResizeRange` `1241-1268`; `testPinchMaximumScale...` `1428-1442` |
| E0 편집 | 각 패널 좌상단 44×44 원형 handle(시각 원 26×26) | drag, minimumDistance 0 | panel 실제 size 측정됨 | panel 중심을 유지하고 top-left 대각 이동량으로 scale 0.3...2.0 | 종료 selection haptic, 이후 merge 판정 | 초안 | `EditablePanel` `RootView.swift:2920-2950`; `scaleFromTopLeadingDrag` `PanelEditingPolicy` | `testTopLeadingResizeKeepsCenter...` `1204-1240` |
| E0 편집 | 시계 패널 본체 | 탭 | 편집 중 | E1 font palette toggle | palette bottom move+opacity | palette 아니오; font 선택은 즉시 예 | `ScreenEditorView` `RootView.swift:2171-2189,2239-2247` | palette boundary `AudioAnalysisTests.swift:1373-1398`; UI 없음 |
| E0 편집 | 분리된 라디오 패널 | 탭 | 1~2 home radios | 해당 channel R0 editor sheet | 없음 | sheet 저장 시 예 | `editableRadioPanels` `RootView.swift:2310-2328` | 없음 |
| E0 편집 | 두 분리 라디오 중 하나 | 이동/resize 종료 | 정확히 2 channels, 미그룹; intersection/min(area) ≥0.40 | 두 중심 평균, 작은 scale로 통합; 두 transforms 동일, `radiosGrouped=true` | medium impact | 초안 | `mergeRadioPanelsIfNeeded` `RootView.swift:2356-2370`; threshold `PanelEditingPolicy` | `testRadioPanelsMergeAtFortyPercentOverlapAndPersistGrouping` `432-459` |
| E0 편집 | 묶인 라디오 전체 | 단일 탭 또는 내부 더블 탭 | 2 channels, grouped | 중심에서 x ±0.11로 분리, 동일 y/scale, grouped false | light impact | 초안 | `editableRadioPanels/splitRadioPanels` `RootView.swift:2289-2308,2372-2379` | `AudioAnalysisTests.swift:432-459` |
| E0 편집 | 빈 두 번째 라디오 placeholder `두 번째 라디오 추가` | 탭 | home radio 1개, 저장 channel 총 2개 이상 | R1 channel management | 없음 | R1 작업 시 예 | `RootView.swift:2331-2352` | 없음 |
| E0 편집 | 각 날씨 group panel | 이동/resize 종료 | 다른 group 존재, overlap ≥0.40 | source/target group ID를 합치고 좌측 piece transform 기준, source/target 중심 평균 | medium impact | 초안 | `mergeWeatherGroup` `RootView.swift:2440-2474` | `testWeatherPanelsMergeAtFortyPercentOverlap` `AudioAnalysisTests.swift:1180-1192` |
| E0 편집 | 2개 이상 piece가 묶인 날씨 panel | 더블 탭 | group pieces >1 | 각 piece 독립 group ID, x를 0.16 간격으로 펼침 | light impact | 초안 | `editableWeatherPanels/splitWeatherGroup` `RootView.swift:2399-2423,2476-2487` | merge만 정책 테스트; split UI 없음 |
| E0 편집 | 상단 `초기화` | 탭 | 편집 중 | 현재 orientation 기본 panel transforms로 **초안만** 교체, bottom control order 유지 | 없음 | 저장 전 아니오 | `ScreenEditorView` `RootView.swift:2266-2279`; `HomeEditorResetPolicy` `91-98` | `testPanelEditorResetPreservesBottomButtonOrder` `917-932` |
| E0 편집 | 상단 `저장` | 탭 | 편집 중 | 진입 당시 orientation의 portrait/landscape layout만 SettingsStore에 반영, 편집 종료 | 0.25초 easeOut | 예 | `saveScreenLayout` `RootView.swift:658-665` | roundtrip `AudioAnalysisTests.swift:1097-1123` |
| E1 팔레트 | 3열 font tile | 탭 | palette 표시 | 10개 중 clock font 선택 | 별도 햅틱 없음 | 예, 즉시 | `fontPalette` `RootView.swift:2508-2527`; choices `AppSettings.swift:5-95` | font bundle/default `AudioAnalysisTests.swift:23-44,721-727` |
| E0 접근성 | 각 panel adjustable | increment/decrement | VoiceOver | scale ±0.1, 0.3...2.0 | selection haptic | 초안 | `EditablePanel` `RootView.swift:3005-3026` | scale policy 테스트 위와 같음 |
| E0 접근성 | 각 panel custom actions | 위/아래/왼쪽/오른쪽 이동 | VoiceOver | x/y ±0.05를 적용한 뒤 최신 editing region 내부로 clamp; merge end callback 실행 | selection haptic | 초안 | `EditablePanel` 이동 action과 `clampTransformToEditingArea` | clamped center 정책 테스트; 접근성 UI 필요 |
| E0 접근성 | 열 수 있는 panel custom `패널 열기` | 활성화 | onTap이 있는 clock/radio/placeholder | font palette 또는 editor/manager open | 일반 코드 경로의 추가 햅틱 없음 | 대상에 따라 | `RootView.swift:3039-3041` | 없음 |

### 2.3 설정·권한·폰트

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| S0 설정 | nav `완료` | 탭 | 항상 | sheet dismiss; Root onDismiss가 recording playback suspension 복구 시도 | 없음 | 아니오 | `SettingsView.body` `SettingsView.swift:41-143`; `RootView.swift:450-451` | 없음 |
| S0 설정 | Hero 상태 pill + `화면 모드 유지` segmented picker | pill은 읽기 전용; picker 선택 | 돌봄 비활성 시 picker disabled | picker가 `자동`/`오브제 유지`/`매이트 유지`를 `setModePreference`로 즉시 적용·저장 | native segmented control; pill은 combined accessibility | 예 | `SettingsHero`, `StandModePreference.title`, `StandViewModel.setModePreference` | 저장 round-trip 및 실제 mode 적용 UI 필요 |
| S0 설정 | `테마` 4개 tile 각각 | 탭 | 항상 | 해당 theme 즉시 선택 | 전체 설정 theme change 0.25초 easeInOut | 예 | `ThemePalettePicker` `SettingsView.swift:882-930`; `SettingsView.swift:142` | roundtrip `AudioAnalysisTests.swift:1150-1165` |
| S0 설정 | `시계 글꼴` row | 탭 | 항상 | S2 push | navigation 기본 | 아니오 | `screenAndClockCard` `SettingsView.swift:145-180` | 없음 |
| S2 글꼴 | 3열 10개 tile | 탭 | 항상 | font 선택 | selection haptic | 예 | `ClockFontSelectionView` `SettingsView.swift:1354-1387`; tile `1389-1442` | bundle/default `23-44,721-727` |
| S0 설정 | `플래시 사용` switch | toggle | OS camera/torch 권한을 별도 요청하지 않음; torch hardware availability는 실제 점등 때 | `torchEnabled` 변경; 켬 설명 `화들짝 모드에서만 켜짐`, 끔 `사용하지 않음` | native switch | 예 | `permissionsCard` `SettingsView.swift:183-243`; torch apply `StandViewModel.swift:1337-1357` | torch policies `AudioAnalysisTests.swift:709-720,1678-1771` |
| S0 설정 | `카메라 사용` switch | on | denied면 OS 설정 열기; 그 외 requestAccess | 허용 시 camera auto sensing 켬/periodic sampling; 거부/unavailable는 상태 문구와 fallback | native switch; OS prompt | 예: 앱 flag, OS 권한은 OS | `permissionsCard/setCameraPermissionEnabled` `SettingsView.swift:200-214,604-617,638-644`; `StandViewModel.swift:1090-1107` | camera policies `639-708,1808-1880`; UI/실기기 없음 |
| S0 설정 | `카메라 사용` switch | off | 항상 | camera cancel, state disabled, last reading clear, sampling cancel | native switch | 예 | `StandViewModel.swift:1090-1098` | sampling policy `1854-1880` |
| S0 설정 | `마이크 사용` switch | on | denied면 OS 설정; unknown이면 OS request; granted only enable | Mate에서 sensing 가능 | native switch/OS prompt | 예/OS | `SettingsView.swift:216-228,619-625,646-660`; `StandViewModel.swift:1109-1112` | interruption policy `AudioAnalysisTests.swift:418-431`; 실권한 없음 |
| S0 설정 | `마이크 사용` switch | off | 항상 | sound sensing flag false, active capture sync stop | native switch | 예 | 같은 근거 | sleep monitor policies `1635-1677` |
| S0 설정 | `위치 정보 사용` switch | on | denied/restricted면 OS 설정; otherwise service requests when needed | current coarse-equivalent location weather | native switch/OS prompt | 예/OS | `SettingsView.swift:230-242,628-635,662-669`; `WeatherService.setLocationEnabled` `WeatherService.swift:106-123` | weather tests `2002-2121` |
| S0 설정 | `위치 정보 사용` switch | off | 항상 | cached weather, location, lastUpdated, task/state clear | native switch | 예 | `WeatherService.swift:106-123` | `testDisablingWeatherLocationClearsCachedLocationData` `2048-2069` |
| S0 설정 | audio error 안 `마이크 권한 열기` | 탭 | access denied | OS app settings | 없음 | OS | `SettingsAudioStatusView` `SettingsView.swift:711-776` | 없음 |
| S0 설정 | `다시 밝혀주기` switch | toggle | 항상; 실제 response는 active Mate | clap, relative rise, movement response enable | native | 예, default true | `detectionCard` `SettingsView.swift:246-291`; callbacks `StandViewModel.swift:418-450` | detector/motion tests `2167-2458` |
| S0 설정 | `코골이·잠꼬대 저장` switch | toggle | recording still requires monitoring and approved classification | approved clips write on/off | native | 예, default true | `SettingsView.swift:271-277`; `AudioCaptureService.configure` `AudioCaptureService.swift:80-98` | recorder/classifier `AudioAnalysisTests.swift:2316-2769` |
| S0 설정 | `수면 소리 열기`/`녹음 N개 보기` | 탭 | 항상 | monitoring pause, radio stop, P0 | 없음 | 아니오 | `SettingsView.swift:279-286` | 없음 |
| S0 설정 | `내장 폰트 저작권` | 탭 | 항상 | S3 | 기본 navigation | 아니오 | `SettingsView.swift:560-570` | license bundle `AudioAnalysisTests.swift:34-44` |
| S3 폰트 목록 | 각 bundled font row | 탭 | 9 bundled fonts; system rounded 제외 | S4 전문 | 기본 navigation | 아니오 | `ClockFontLicensesView` `SettingsView.swift:1455-1488` | `AudioAnalysisTests.swift:34-44` |
| S4 전문 | 본문 | long press/select/copy(OS text selection) | license file load success | license text 선택 가능; 실패면 `라이선스 전문을 불러올 수 없습니다.` | OS selection | 아니오 | `FontLicenseDetailView` `SettingsView.swift:1490-1523` | 파일 존재만 `34-44` |
| S0 설정 | `날씨 데이터 Open-Meteo` | 탭 | URL 생성 가능(상수 force unwrap) | 외부 browser로 `https://open-meteo.com/` | OS transition | 아니오 | `SettingsView.swift:572-580` | 없음 |
| S0 설정 | `추천 설정 복원` | 탭 | 항상 | A1 표시; 확정 시 `AppSettings.recommended`로 교체하여 radio 포함 reset. 기존 migration marker UserDefaults는 건드리지 않음 | destructive red; dialog native | 예 | `SettingsView.swift:590-601,126-137`; `SettingsStore.restoreRecommendedValues` `AppSettings.swift:860-867` | defaults/migrations `AudioAnalysisTests.swift:721-728,1013-1080` |
| S0 설정 | ≥720pt content width | 회전/큰 화면 | width threshold | radio card full width, 아래 4 cards 2열; <720은 1열 | layout reflow | 아니오 | `SettingsView.body` `SettingsView.swift:41-74` | iPad home controls only `889-916`; settings grid UI 없음 |
| S0/S2 | Dynamic Type | OS 글자 크기 | native SwiftUI; explicit 3-column font grid remains | text fixedSize/lineLimit/minScale where coded; 전체 완전 무잘림은 미검증 | native | OS | `SettingsView.swift:17,41-143,932-1180,1354-1442` | XCUITest 없음 |

### 2.4 설정의 인터넷 라디오, 채널 관리·편집

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| S0 라디오 card | channel row 왼쪽 본문 | 탭 | 저장 channel | idle/failed면 play; loading/reconnecting/playing이면 same channel stop | 별도 햅틱 없음; active bg/stroke | 재생 아니오 | `inlineRadioChannelRow` `SettingsView.swift:342-395`; model `StandViewModel.swift:826-837` | reconnect/mutation `AudioAnalysisTests.swift:371-381,460-528` |
| S0 라디오 card | channel row 우측 48×48 연필 | 탭 | 저장 channel | S1 inline 수정 펼침 | 0.22초 easeInOut | 초안 | `SettingsView.inlineRadioChannelRow` | 없음 |
| S0 라디오 card | `첫 채널 추가/채널 추가` | 탭 | editor 닫힘, channels <2 | S1 blank editor | 0.22초 easeInOut | 초안 | `SettingsView.swift:322-333,496-502` | max count `AudioAnalysisTests.swift:334-370` |
| S1 inline | `닫기` | 탭 | editor open | 초안/validation clear, collapse | 0.22초 easeInOut | 아니오 | `SettingsView.swift:398-474,512-518` | 없음 |
| S1 inline | name/address TextField | 입력 | name optional; URL required | local draft, input change clears error | keyboard native | 아니오 | `SettingsView.swift:412-430,472-473` | validation `AudioAnalysisTests.swift:86-122` |
| S1 inline | PasteButton | 탭 | clipboard String provider | first string copied to address, error clear | OS PasteButton consent/UI | 아니오 | `SettingsView.swift:432-439` | 없음 |
| S1 inline | `웹에서 찾기` | 탭 | 항상 | B0; browser never auto-fills draft | fullScreenCover | 아니오 | `SettingsView.swift:440-447,102-104` | browser address tests `123-197` |
| S1 inline | trash 48×48 | 탭 | editing existing | A0 confirmation | native | 아니오 until confirm | `SettingsView.inlineRadioEditor`, root confirmation dialog | 없음 |
| S1 inline | `저장` | 탭 | config validates; maximum two enforced by model settings | add: select only if first; edit: stable ID; success closes + success haptic; failure inline message + error haptic | notification success/error | 예 on success | `saveInlineRadioChannel` `SettingsView.swift:520-544`; config `InternetRadioConfiguration.swift:3-86` | validation/channels/selection `AudioAnalysisTests.swift:86-370` |
| R0 sheet | fields/Paste/`웹에서 주소 찾기` | 입력/탭 | same validation; shared import may prefill | draft only; browser separate | native | 아니오 until save | `InternetRadioConfigurationView` `RootView.swift:2530-2627` | import `AudioAnalysisTests.swift:529-609` |
| R0 sheet | `취소` | 탭 | always; shared import interactive swipe dismiss disabled | shared draft clear; sheet dismiss | native | pending app-group draft clear | `RootView.swift:2640-2645,2668-2669`; store `InternetRadioConfiguration.swift:89-125` | shared store tests `557-609` |
| R0 sheet | `저장` | 탭 | valid | existing ID update or add/select; pending shared clear; dismiss | no explicit haptic | 예 | `RootView.swift:2646-2649,2676-2696`; `StandViewModel.swift:937-957` | shared import/mutation tests `460-609` |
| R0/R2 | delete button | tap then A0 confirm | existing and deletion allowed | active channel stops; remove; R2/R0 dismiss | R1 direct delete uses success haptic; dialog paths no explicit haptic | 예 | `RootView.swift:2629-2666`; `SettingsView.swift:1899-1936`; `StandViewModel.swift:911-925` | mutation policy `460-528` |
| R1 list | empty `첫 채널 추가`, toolbar `채널 추가` | 탭 | count<2 | R2 add push | native | 초안 | `InternetRadioChannelManagementView` `SettingsView.swift:1569-1679` | max count test `334-370` |
| R1 list | channel row 연필, context `채널 수정`, trailing swipe `수정` | tap/long press menu/swipe then tap | existing | R2 edit push | native context/swipe | 초안 | `SettingsView.swift:1591-1606,1681-1744` | 없음 |
| R1 list | context/trailing swipe `삭제` | long press/swipe then tap | existing; full swipe disabled | confirmation 표시; `채널 삭제` 확정 뒤 delete, active면 stop | success notification haptic | 확정 후 예 | `InternetRadioChannelManagementView.pendingDeletion/confirmationDialog/delete` | mutation policy + 취소/확정 UI 필요 |
| R1 list | EditButton reorder handle | drag row | channels >1 | stable channel ID moved; first/second home panels reorder | selection haptic | 예 | `SettingsView.swift:1608,1643-1646,1801-1809`; `AppSettings.moveInternetRadioChannel` `AppSettings.swift:629-730` | mutations `299-333` |
| R1 list | row 본문 VoiceOver | custom `채널 수정`; selected state | always | editor open; 일반 탭으로 홈 선택하지 않으며 hint도 현재 표시/순서 변경 의미만 설명 | none | 아니오 | `InternetRadioChannelManagementView.channelRow` | TalkBack/VoiceOver 문구 확인 |
| R1/R2 | `웹에서 주소 찾기` | tap | always | B0 | fullScreenCover | no | `SettingsView.swift:1616-1625,1883-1892` | browser tests `123-197` |
| R2 editor | fields/Paste | input/tap | same limits | local draft; input clears validation | native | no until save | `SettingsView.swift:1849-1881,1937-1938` | validation `86-122` |
| R2 editor | toolbar `저장` | tap | valid | add/update/select true; dismiss | no explicit haptic | yes | `SettingsView.swift:1913-1918,1941-1955`; manager save `1786-1794` | channel tests `198-370` |

### 2.5 내장 브라우저

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| B0 브라우저 | 상단 왼쪽 44×44 원형 | tap | popup open / history / none 순 | popup close; else goBack; else browser dismiss | none | retained ephemeral WebView may persist for process only | `browserBackOrCloseButton/handleBackOrCloseTap` `InternetRadioBrowserView.swift:133-161,261-274` | address/favorite only `AudioAnalysisTests.swift:123-197`; gesture UI none |
| B0 브라우저 | same | 0.5s long press | popup open이면 popup close, 아니면 browser dismiss; history와 무관 | media pause then dismiss | none | no | `browserBackOrCloseGesture` `InternetRadioBrowserView.swift:239-254` | none |
| B0 접근성 | same button custom action | default activate / `브라우저 닫기` | always | default is tap semantics; custom always dismiss | none | no | `InternetRadioBrowserView.swift:147-160` | none |
| B0 브라우저 | address TextField (`44...56pt`, horizontal padding 10) | type + keyboard Go | input non-empty ≤2048 | focus clear, favorites close; scheme HTTPS validate; no-scheme dot domain adds HTTPS; other text Google query; invalid error panel | native keyboard | no | `addressBar/loadAddress` `InternetRadioBrowserView.swift:68-114,276-280`; `InternetRadioBrowserAddress` `967-1051` | `testInternetRadioBrowserAddressAcceptsOnlyCredentialFreeHTTPS` `AudioAnalysisTests.swift:123-171` |
| B0 브라우저 | primary 44×44 accent circle | tap | loading / not loading | stop load and progress reset / submit current address | none | no | `browserPrimaryAddressButton/primaryAddressAction` `InternetRadioBrowserView.swift:163-179,282-288` | none |
| B0 브라우저 | same | 0.5s long press | clipboard has String or URL after trim | paste address and immediately load; missing clipboard → `복사한 웹 주소가 없습니다.` | none | OS clipboard read | `primaryAddressButtonGesture/copiedAddress` `InternetRadioBrowserView.swift:226-237,290-304` | none |
| B0 브라우저 | refresh 44×44 | tap | `hasLoadedPage`; disabled before page | clear error, WebView reload | none | no | `InternetRadioBrowserView.swift:90-98`; session `691-694` | none |
| B0 브라우저 | star 44×44 | tap | always | B1 toggle | 0.18s easeInOut, top move+opacity | no | `browserFavoritesButton` `InternetRadioBrowserView.swift:181-203` | favorites constants `AudioAnalysisTests.swift:172-197` |
| B1 favorites | X button | tap | panel visible | panel close | 0.18s easeInOut | no | `favoritesPanel` `InternetRadioBrowserView.swift:306-323` | none |
| B1 favorites | one of 4 ≥56pt rows | tap | panel visible | address set, focus clear, panel close, URL open | transition inherited | no | `InternetRadioBrowserView.swift:325-357`; defaults `936-964` | `AudioAnalysisTests.swift:172-197` |
| B2 message | X | tap | error exists and favorites hidden | error clear | none | no | `browserMessagePanel` `InternetRadioBrowserView.swift:375-401` | none |
| B0 WebView | page content | horizontal edge swipe/back-forward gesture | WebView history supports | back/forward navigation | WK native | non-persistent data store; process retained instance only | `InternetRadioWebView.makeUIView` `InternetRadioBrowserView.swift:427-458` | no UI test |
| B0 WebView | page link with target blank/window.open | tap | HTTPS, not download | same WebView loads popup URL, remembers return URL, x becomes popup close | native page | no | `WKUIDelegate.createWebViewWith` `InternetRadioBrowserView.swift:881-904` | no |
| B0 WebView | file input/upload/drop/paste files | page input | any page | injected JS disables file input/click/showPicker and blocks file pointer/touch/drop/paste; iOS 18.4 open panel returns nil | none | no | `fileUploadBlockingScript` `InternetRadioBrowserView.swift:560-622`; openPanel `906-914` | no |
| B0 WebView | media capture/motion permission | webpage request | any | always deny | OS prompt should not appear | OS no grant | `WKUIDelegate` `InternetRadioBrowserView.swift:916-933` | no |
| B0 browser | app active→inactive/background | system lifecycle | B0 alive | page audio/video pause; active resumes retained media session | JavaScript/media session helper, no visible anim | no | `InternetRadioBrowserView.body` `56-62`; store/session `472-558,713-721` | no real-site test |
| B0 WebView | navigation/download/auth/process failures | page/system | HTTP, credentials, file/custom scheme, download, attachment, unsupported MIME, non-server-trust auth, crash | cancel; exact error panel; server trust uses default OS handling only; cancelled URL error is not shown | B2 transition top+opacity | no | navigation delegate `InternetRadioBrowserView.swift:773-879`; errors `754-770,1036-1050` | validation only `123-171`; failures untested |

브라우저 설정은 `WKWebsiteDataStore.nonPersistent`, JS 허용, mobile content, user action required for all media, inline playback 허용, AirPlay/PiP/fullscreen element 금지, fraudulent-site warning 켬, link preview 켬이다 (`InternetRadioBrowserView.swift:427-455`). Android는 ephemeral profile/cookie·cache cleanup, HTTPS-only interception, download listener reject, file chooser reject, geolocation/media permission reject, popup same WebView, process death recovery를 각각 구현·검증해야 한다.

### 2.6 수면 소리·선택·재생·삭제

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| P0 수면 소리 | nav `닫기` | tap | always | dismiss; player stops on disappear; Root/Settings onDismiss resumes monitor if suspension present | none | no | `RecordingsView.swift:105-114,221-223`; model `StandViewModel.swift:813-824` | no UI/integration test |
| P0 empty | full content unavailable | no input | clips and sessions both empty | `저장된 수면 소리가 없습니다`, explanation | none | no | `RecordingsView.swift:38-45` | no |
| P0 list menu | `전체 선택` | tap | clips exist, !merging | all mergeable originals selected | selection dock appears | no | `RecordingsView.swift:115-145`; policy `515-523` | no direct policy test |
| P0 list menu | `오늘 선택` | tap | !merging, today originals nonempty | today originals selected | dock | no | same | merge library test `AudioAnalysisTests.swift:3084-3210` |
| P0 list menu | `선택 모두 해제` | tap | selection nonempty, !merging | clear | dock disappears | no | same | no |
| P0 list menu | `전체 삭제` | tap + A2 `모두 삭제` | !merging | player stop; delete every stored m4a including not indexed and pending dir; preserve current open session per library; partial failure surfaced A3 | native confirmation | file deletion + manifest update | `RecordingsView.swift:137-167`; `RecordingLibrary.deleteAll` `RecordingLibrary.swift:413-449` | `testDeletingAll...` `AudioAnalysisTests.swift:2832-2955` |
| P0 오늘 card | `오늘 소리 합치기` | tap | playback enabled, !merging, today originals≥2 | async chronological merge, originals remain; status/error | ProgressView while busy | new file | `todayMergeCard/mergeTodayRecordings` `RecordingsView.swift:265-309,524-538`; `RecordingLibrary.mergeToday` `RecordingLibrary.swift:491-493` | merge `AudioAnalysisTests.swift:3084-3210` |
| P0 selection card | header whole button | tap | originals exist | selection tools toggle | 0.22s easeInOut, chevron rotates | no | `RecordingsView.swift:311-378` | no |
| P0 selection tools | `모두 고르기`, `오늘만 고르기`, `선택 풀기` | tap | respective disabled rules | selection set update | none | no | `RecordingsView.swift:339-356` | no |
| P0 selection tools | `합친 뒤 원본 지우기` | tap + A2 confirm | playback enabled, !merging, selected≥2 | make selected merge then delete original sources; partial deletion error keeps actual state | red button; ProgressView/dock busy | new file + deletes | `RecordingsView.swift:362-373,181-192,539-559`; library merge `450-489` | merge + partial delete `AudioAnalysisTests.swift:3062-3210` |
| P0 session card | header entire row | tap | session exists | expand/collapse original clip rows | 0.24s easeInOut, top move+opacity, chevron rotation | no | `sessionCard` `RecordingsView.swift:380-421`; header `740-824` | session grouping tests `2773-3056`; UI no |
| P0 merged card | header | tap | merged clips exist | expand/collapse merged rows | 0.24s easeInOut, top move+opacity | no | `mergedRecordingsCard` `RecordingsView.swift:422-470` | no |
| P0 clip row | left checkbox 48×48 | tap | original, mutation not disabled | select/unselect | dock update | no | `RecordingRow` | no UI test |
| P0 clip row | play circle 48×48 or description body | tap | playback enabled | inactive/new: audio session playback, play; active playing: pause; active paused: resume | active row accent background; P2 dock | no | `RecordingRow`; `RecordingPlayer.toggle` | boost default test; actual playback no |
| P0 clip row | ellipsis menu `공유` | tap | mutation enabled | OS share sheet with local file URL | OS | OS external action; source file remains | `RecordingsView.swift:1002-1014` | no |
| P0 clip row | ellipsis `삭제` | tap + A2 confirm | mutation enabled | if playing same stop, file delete, manifest reference remove/reload; error A3 | native | file delete | `RecordingsView.swift:193-209,471-514`; `RecordingLibrary.swift:384-412` | partial/batch delete `AudioAnalysisTests.swift:3062-3083` |
| P1 selection dock | X 48×48 | tap | selection | clear | dock disappears | no | `RecordingSelectionDock.clearButton` | no |
| P1 selection dock | `한데 묶기` | tap | selected≥2, playback enabled, !busy | merge originals preserved | busy ProgressView | new file | `RecordingsView.swift:88-97,658-711`; merge `524-559` | `3084-3210` |
| P1 selection dock | trash 48×48 | tap + confirm | !busy | delete selected | red, native dialog | file delete | `RecordingSelectionDock.deleteButton` | delete tests above |
| P2 playback dock | play/pause 48×48 | tap | active clip | pause/resume | no | no | `PlaybackProgressBar.playbackButton`; player `RecordingPlayer` | no UI test |
| P2 playback dock | speaker `2×` 48×48 | tap | active clip | playerNode volume 2.0/1.0; default true | accent state | no | `PlaybackProgressBar.boostButton`; `RecordingPlayer.toggleBoost` | `testRecordingPlaybackBoostDefaultsToTwoTimes` |
| P2 playback dock | Slider | drag/tap adjustable | active clip | seek 0...duration, reschedule retaining play/pause state | native slider | no | `RecordingsView.swift:1086-1103`; `RecordingPlayer.seek` `RecordingLibrary.swift:798-804` | no |
| P2 playback dock | X 48×48 | tap | active clip | stop/reset URL/time/duration/play state, deactivate audio session | no | no | `PlaybackProgressBar.closeButton`; `RecordingPlayer.stop` | no |
| P0 large text | today card/action grid/docks | Dynamic Type accessibility sizes | OS setting | today card falls vertical; action grid adaptive min 140 vs 108; merge button fills width; other fixed sizes remain source-defined | native reflow | OS | `RecordingsView.swift:10,265-309,339-343` | no UI test |

### 2.7 공유 확장·위젯·OS 경로

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| X0 공유 확장 | `라디오 주소로 가져오기` ≥50pt | tap | Web URL 1개 loaded and same HTTPS/no-credential validation passes | app-group pending config latest-wins 저장; button `가져옴`; status `S.tand를 열어...`; 0.45초 후 extension complete | delayed close, no haptic | yes, app-group UserDefaults | `ShareViewController.configureView/load/saveAddress` `STandRadioShare/ShareViewController.swift:16-177`; store `InternetRadioConfiguration.swift:89-125` | shared store/import `AudioAnalysisTests.swift:529-609`; extension UI no |
| X0 공유 확장 | `취소` | tap | always | extension cancelled with `NSUserCancelledError` | OS | no | `ShareViewController.swift:64-68,179-183` | no |
| X0 공유 확장 | load/validation failure | no/tap unavailable | missing URL, provider error, invalid URL, app-group save fail | exact status message, import button disabled; existing app settings unchanged | no | no | `ShareViewController.swift:105-169` | malformed/pending tests `557-609` |
| H0 from shared | app becomes active | system/open app | valid pending app-group config | R0 automatically opens; exact existing stream reuses stable ID/name until explicit save; cancel clears pending | sheet native | save only on explicit save | `StandViewModel.appDidBecomeActive/importSharedInternetRadioIfNeeded` `StandViewModel.swift:574-577,969-975`; `RootView.swift:511-514` | `AudioAnalysisTests.swift:529-609` |
| W0 widget | circular widget entire area | tap | installed accessoryCircular widget | `stand://open`, app foreground; URL itself has no special routing beyond launch | OS | no | `STandWidget.swift:22-62`; URL scheme `Info.plist:9-19` | no widget UI test |

### 2.8 확인 대화상자·오류 alert

| 화면 | 정확한 영역 | 사용자 입력 | 실행 조건 | 결과 | 애니메이션·햅틱 | 저장 여부 | Swift 근거 | 테스트 근거 |
|---|---|---|---|---|---|---|---|---|
| A0 S0 inline channel delete | system confirmation dialog의 `채널 삭제`/`취소` | tap | pending channel nonnil | delete: active stop, channel remove, matching inline editor close; cancel clears pending | platform dialog; explicit haptic none | delete yes | `SettingsView.body` `SettingsView.swift:105-125` | mutation policy `AudioAnalysisTests.swift:460-528`; dialog UI none |
| A0 R0 channel delete | system confirmation `채널 삭제`/`취소` | tap | `allowsDeletion` existing channel | delete callback then sheet dismiss / no-op cancel | native | delete yes | `InternetRadioConfigurationView` `RootView.swift:2629-2666` | policy only |
| A0 R2 channel delete | system confirmation `채널 삭제`/`취소` | tap | existing configuration | delete callback then editor pop / cancel | native | delete yes | `InternetRadioChannelEditorView` `SettingsView.swift:1899-1936` | policy only |
| A1 restore | `추천 설정 복원`/`취소` | tap | S0 restore requested | full app recommended values incl channels reset / no change | native destructive, no explicit haptic | confirm yes | `SettingsView.body` `SettingsView.swift:126-137`; `SettingsStore.restoreRecommendedValues` `AppSettings.swift:854-868` | migrations/default tests `AudioAnalysisTests.swift:721-1180` |
| A2 all recordings | `모두 삭제`/`취소` | tap | menu request, !merge | player stop, library deleteAll, selection/session expansion clear; error→A3 | native destructive | files/manifest | `RecordingsView.swift:148-167` | delete tests `AudioAnalysisTests.swift:2832-2955` |
| A2 selected recordings | `선택 항목 삭제`/`취소` | tap | selection request, !merge | selected actual files delete; partial error→A3 | native | files/manifest | `RecordingsView.swift:168-180` | partial delete `3062-3083` |
| A2 merge then delete | `합치고 지우기`/`취소` | tap | selected≥2 and enabled | merge remains, source delete attempt; partial error→A3 | native | new file+deletes | `RecordingsView.swift:181-192` | merge/delete `3062-3210` |
| A2 single recording | `녹음 삭제`/`취소` | tap | pending clip | stop if playing, delete/reload / pending nil | native | file/manifest | `RecordingsView.swift:193-209` | delete policy tests |
| A3 operation failure | alert `확인` | tap | mergeErrorMessage nonnil | dismiss and clears displayed error; message exact localized error or `알 수 없는 오류가 발생했습니다.` | native alert | no | `RecordingsView.swift:210-220`; errors `RecordingLibrary.swift:169-189` | error policy tests `3062-3210`; alert UI none |

모든 confirmation의 title/message/button 원문은 위 Swift 범위와 17절 전수 원장에 보존한다. Android에서 Snackbar만으로 대체하거나 destructive confirm을 생략하지 않는다. R1 list context/swipe delete도 0.25.0부터 동일한 confirmation을 거친다.

## 3. 모든 표시 문구·버튼 문구

아래는 동적 값 자리표시자를 보존한 사용자 가시 문자열 목록이다. SF Symbol 이름은 시각 사양 절에 별도 기재한다.

### 3.1 홈·편집

- 상단/상태: `오브제 모드 잠금`, `오브제 모드`, `매이트 모드`, `화들짝 모드`, `자동 기능 꺼짐`, `S.tand`, `배터리 --%/N%`, `N · 밝기 N%` (`RootView.swift:527-562,3311-3332`).
- 시작: `S.tand가 곁에 있을게요`, `시작하면 오브제와 매이트 모드를 오가며 시간·날씨와 잠자리를 돌봅니다.`, `S.tand 시작` (`RootView.swift:566-595`).
- HUD: `앱 밝기`, `라디오 볼륨`, `시계 크기`와 퍼센트 (`RootView.swift:1046-1123`).
- 하단: `녹음 목록 보기`, `녹음 없음`/`N개 녹음`, `설정 열기`; 숨김 문구 `탭하면 자연스럽게 어두워짐`/`탭하면 조명 켜짐` (`RootView.swift:856-960`).
- banner: `충전이 연결되었습니다. S.tand 시작을 눌러 다시 시작하세요.`, `배터리가 20% 이하라 보호를 위해 감지와 불빛을 중지했습니다.`, writer가 제공하는 녹음 오류 (`RootView.swift:962-993`).
- 편집: `초기화`, `세로 패널 편집`/`가로 패널 편집`, `저장`, `패널 이동·크기 조절 · 라디오 연필을 눌러 주소 편집`, `두 번째 라디오 추가` (`RootView.swift:2239-2284,2331-2352`).
- 접근성 이름: `홈 화면 제어`, `오브제와 매이트 전환`, `테마 전환`, `화면 편집 열기`, `시계 크게`, `시계 작게`, `시계/초/날짜/배터리/날씨 패널`, `패널 크기 조절`, 이동 4방향, `패널 열기` (`RootView.swift:757-783,2171-2235,2866-3050`).

### 3.2 설정

- nav/card: `설정`, `완료`, `화면과 시계`/`테마와 시계 글꼴을 바꿉니다`, `권한 설정`/`필요한 기능만 선택해서 사용합니다`, `잠꼬대와 코골이`/`매이트 모드에서만 작동합니다`, `인터넷 라디오`, `정보`/`개인정보, 저작권과 앱 정보를 확인합니다` (`SettingsView.swift:41-304,546-552`).
- 화면: `테마`, `시계를 더블 터치하면 테마가 바뀝니다.`, `시계 글꼴`, `홈 화면을 길게 누르면 시계와 날씨 같은 정보 패널을 편집할 수 있습니다.` (`SettingsView.swift:145-180`).
- 권한: `플래시 사용`, `화들짝 모드에서만 켜짐`, `사용하지 않음`, `카메라 사용`, `마이크 사용`, `위치 정보 사용`; 정확한 상태 문구는 `cameraAmbientStatusText`, `microphonePermissionText`, `locationPermissionText` 전 분기 (`SettingsView.swift:183-243,604-635`).
- 감지: `다시 밝혀주기`, `박수, 핑거스냅, 뒤척임과 기기 움직임에 반응`, `코골이·잠꼬대 저장`, `후보 소리가 날 때 필요한 구간만 저장`, `수면 소리 열기`/`녹음 N개 보기`, 1분 학습 설명 (`SettingsView.swift:246-291`).
- audio status의 전 문구: `감지 멈춤`, `오브제 모드`, `마이크 대기`, `마이크 준비 중`, `소리 저장 중`, `소리 감지 중`, `소리 감지 안 됨`, `마이크 권한 열기`, `소리와 뒤척임 감시는 매이트 모드에서만 작동합니다.`, `최근 감지 · 코골이/잠꼬대 후보/뒤척임/기타 소리`, `방 소리 익히는 중 · N%`, `자동 적응 완료 · 평소 N dB`, `설정에서 마이크 권한을 허용해 주세요.`, `레벨 N%` (`SettingsView.swift:711-776,1444-1453`).
- 정보: `버전`, `내장 폰트 저작권`, `원문 포함`, `날씨 데이터`, `Open-Meteo`, privacy/safety 3문장, `추천 설정 복원`; confirm title/message/buttons (`SettingsView.swift:546-601,126-137`).
- 글꼴: `시계 글꼴`, 10개 display names, `폰트 저작권`, `내장 폰트 저작권`, `라이선스 전문`, 장문 4개 설명, load failure (`SettingsView.swift:1354-1523`; 이름 `AppSettings.swift:5-95`).

### 3.3 라디오·브라우저·녹음·공유

- 라디오의 모든 가시 field/button/help/error/status 문구는 `SettingsView.swift:294-544,1547-1957`, `RootView.swift:2530-2696`, validation errors `InternetRadioConfiguration.swift:3-67`가 단일 근거다. 반드시 `대기 중/연결 중/재생 중/자동 재연결 중/연결 실패`, `이름 (선택)`, `https://…`, `웹에서 찾기/주소 찾기`, `채널 추가/수정/삭제`, 삭제 confirm 문구를 그대로 포함한다.
- 브라우저의 모든 고정 문구는 `InternetRadioBrowserView.swift:68-401,723-865,936-1051`: `웹 주소 입력`, accessibility `이전 페이지/팝업 닫기/브라우저 닫기/새로고침/로딩 중지/주소로 이동/복사한 주소로 이동`, `즐겨찾기`, 4개 favorite 이름·URL, 안내 및 오류 전 분기다.
- 수면 소리의 모든 가시 문구는 `RecordingsView.swift:33-378,422-590,649-824,891-1131`: empty, summary, today, selection, session, timeline, row/menu, dock, 4개 confirmation, failure alert, playback labels를 포함한다.
- 공유 확장 모든 문구는 `STandRadioShare/ShareViewController.swift:16-177`; 위젯 문구는 `STandWidget/STandWidget.swift:22-62`다. Android string resource를 만들 때 이 범위를 자동 추출해 대조해야 한다.

## 4. 디자인 토큰·크기·간격·투명도·애니메이션

### 4.1 테마와 배경

| 항목 | 정확한 값 | Swift 근거 |
|---|---|---|
| 테마 순서/표시명/accent | color `오렌지` accent system orange; grayscale `그레이` accent white; midnight `미드나이트` RGB(.38,.68,1); sage `세이지` RGB(.55,.78,.62) | `StandDisplayTheme` `AppSettings.swift:97-126` |
| 홈 color radial | center, start 20, end 700; RGB(1,.62,.28)×intensity, RGB(.95,.27,.06)×intensity×.72, black opacity `1-intensity×.22` | `LampBackground` `RootView.swift:997-1043` |
| 홈 grayscale radial | white .72×intensity×.72; white .30×intensity×.64; black `1-intensity×.18`; root grayscale(1)도 적용 | 같은 근거; `RootView.swift:426` |
| 홈 midnight radial | RGB(.28,.58,1)×intensity×.86; RGB(.08,.20,.58)×.78; RGB(.01,.02,.09) opacity `1-intensity×.18` | `RootView.swift:1030-1035` |
| 홈 sage radial | RGB(.60,.82,.64)×.80; RGB(.20,.43,.30)×.72; RGB(.025,.075,.055) opacity `1-intensity×.18` | `RootView.swift:1036-1041` |
| 설정 배경 | base RGB(.115,.085,.078); topLeading→bottomTrailing `[accent .20, RGB(.16,.115,.10), RGB(.085,.075,.075)]`; topTrailing radial start20/end640 `[accent .24,.06,clear]`, screen blend | `StandSettingsBackground` `SettingsView.swift:778-803` |
| 브라우저 배경/panel | RGB(.105,.078,.071); white .09 | `InternetRadioBrowserView.swift:403-409` |
| launch | black asset RGB(0,0,0,1) | `Assets.xcassets/LaunchBackground.colorset/Contents.json:1-16` |

### 4.2 공통 표면·시계·날씨·라디오

- `FlipPanelSurface`: continuous rounded rect; top→bottom white opacity normal `.095→.052`, dim `.014→.008`; 두 rectangle mask 사이 기본 gap4; white 1pt stroke normal .08/dim .018; **shadow modifier는 없다** (`FlipPanelSurface` `RootView.swift:3281-3308`). 패널 별 corner/split은 호출부가 결정한다. Android에서 단순 단색 카드나 임의 shadow로 대체하면 parity 실패다.
- 홈 top padding portrait 18/landscape 20; horizontal 20/32; bottom `portrait 30 (=18+12)`, landscape `18 (=6+12)`; bottom row spacing 6 (`RootView.swift:303-365`; `StandControlLayoutMetrics` `100-115`).
- top brand icon 28, continuous radius 23%, white stroke .12/0.7; `S.tand` rounded headline semibold tracking .8; mode caption2 semibold white .62; 전체 white .82, controls hidden .18, 0.3초 (`RootView.swift:4-18,527-562`).
- footer height 12, font 8.5 medium monospaced, white .28; build/brightness accessibility combined (`RootView.swift:344-365`).
- bottom control tile height 60; item font 10.5/status 8.5; 현재 visible order는 legacy flashlight/brightness를 필터링해 recordings/settings만 남긴다 (`RootView.swift:891-949`; `AppSettings.swift:156-179`).
- portrait bottom column policy width<700: 4 columns, 그 외 8; actual two visible tiles each one column and wrapping is centered. iPad portrait single compact row policy test exists (`RootView.swift:117-187,197-270`; `AudioAnalysisTests.swift:889-916`).
- date width portrait 200/landscape 240, rounded subheadline medium, min scale .75 (`RootView.swift:21-38`).
- burn-in offset는 매 60초 `(0,0),(3,-2),(5,1),(2,3),(-2,3),(-5,1),(-3,-2),(0,-3)` px 순환 (`BurnInProtection` `RootView.swift:59-75`; test `AudioAnalysisTests.swift:8-17`).
- 날씨 셀은 portrait `282/3=94`, landscape `370/3≈123.333`; split 4/3; metadata 18, top/bottom inset 7/8, temperature optical y 2/2.5 (`WeatherPanelGeometry` `RootView.swift:1753-1775`). 아이콘 34/40, 온도 28/34 semibold rounded, 체감 11/13, 상태 17/20, 상태 최대 2줄 minScale .7 (`WeatherPieceContent` `1890-1926`).
- 위치 marquee: icon 9/11, font 11/13 rounded medium, spacing5; overflow only 18pt/s, 양끝 pause1.2초, 30fps TimelineView (`RootView.swift:1777-1880`; test `AudioAnalysisTests.swift:2070-2121`).
- InternetRadioPanel은 144×60, corner13, unscaled 최소 hit44; HStack8, h-pad11, icon17 semibold/width24, name10.5 semibold minScale.65, status8.5 medium, foreground normal white .78/dim white .46×dimIntensity, status white .52/.40; surface split2. 편집 badge pencil17 black .72/orange offset(6,-6). grouped divider white dim .025/normal .08 width1 (`InternetRadioPanelMetrics/InternetRadioPanel` `RootView.swift:1393-1580`; grouped `1581-1653`).
- clock font별 PostScript 이름/vertical offset: `ClockFontChoice` 전 10 case와 `font(size:)`, `clockVerticalOffset` `AppSettings.swift:5-95`. bundle 9 files는 `Info.plist:62-73`; Android도 같은 원본 파일과 라이선스 고지를 포함해야 한다.
- flip clock은 12시간제로 hour `00` 대신 `12`; portrait H spacing8/card126×92/font64/radius18/text split4/colon48, landscape spacing12/card164×116/font82/radius22/text split3/colon62. 분침/숫자 `.snappy(.42)`. seconds는 portrait48×36, landscape58×42; background 때 font18/22·radius11/13·split2/2.5, clock 위일 때 font13/16·background 없음; opacity normal .40/dim .16, numeric transition/easeInOut .18. overlap 판정 clock 288×92/374×116 bounds를 8 확장 (`FlipClockFace/ClockSecondsPlacement/ClockSecondsPanel/FlipClockCard` `RootView.swift:3150-3267`). visual snapshot은 없다 (`AudioAnalysisTests.swift:18-44,1930-1948`).

### 4.3 HUD·설정·녹음·브라우저

- 밝기/볼륨 HUD: HStack spacing9, icon16 semibold, title13 semibold rounded, value14 bold rounded monospaced, white .92, horizontal pad15, height46, black .48 capsule, white .14 1pt stroke (`RootView.swift:1046-1102`).
- 시계 크기 HUD: VStack8, icon title2, caption/caption2, white .72, h-pad22/v-pad16, black .58, continuous radius18 (`RootView.swift:1104-1123`).
- editor backdrop black .32, crosshair white .16 at .5pt; panel dash stroke orange .45 line1 `[4]`; handle orange .9 26 in 44 target, glyph9 bold black .72 (`RootView.swift:2163-2169,2866-2950`). Toolbar h46, h-pad20, ultraThinMaterial capsule; outer inset portrait18/landscape14 (`RootView.swift:2266-2284`).
- Settings root spacing14; h-pad width≥720 24 else14; top8; bottom max(28,safe+16). Card header pad15, divider white .10/1, content spacing14/pad15, gradient white .16→.085, radius22, stroke white .16/1 (`SettingsView.swift:41-74,932-998`). Hero icon58, H spacing14, title24 rounded bold, subtitle caption white .56 (`SettingsView.swift:805-861`).
- Settings radio row min58, pad h10, radius15; idle fill white .06/stroke .08, active accent .15/.30; play icon20 within34, pencil34 (`SettingsView.swift:342-395`). Inline editor spacing10/pad12, black .12 radius16; fields pad11 white .08 radius12; save min42 (`398-474`).
- theme tile exact 4-column palette, swatch and labels `ThemePalettePicker` `SettingsView.swift:882-930`; font preview 3 columns spacing8, tile radius15, preview h52 and 23pt selected styling `ClockFontSelectionView/ClockFontGridTile` `1354-1442`.
- Audio meter 12×58; track white .08; value min4 to58; gradient accent .42→1; 0.12s linear (`SettingsView.swift:1330-1351`).
- Recording root h-pad14, top10, bottom30, stack12; panels use `RecordingBackground/RecordingPanelSurface` exact values `RecordingsView.swift:592-657`; summary icon54 radius14, outer card radius22/pad16 (`231-263`). Row min controls 40~42×44, pad h10/v7, radius15, active accent .18/idle white .08 (`951-1022`). Timeline exact bars/gradients/shadows `826-949`.
- Browser bar h-pad12/v9, spacing7; controls 44; address 44...56; separator1 and progress2; progress animation .18 and load visibility .16 (`InternetRadioBrowserView.swift:15-21,68-130`). Favorites card pad12/radius10/stroke .22/shadow black .18 radius14 y6; rows min56 radius8 (`306-373`). Error min48 material radius8 orange .30 stroke (`375-401`).

### 4.4 애니메이션·햅틱 완전 목록

| 발생 | 값 | 근거 |
|---|---|---|
| 테마 변경 홈 | easeInOut .28s + light impact | `RootView.swift:445,743-749` |
| 홈 lamp intensity | linear .08s; direct mode/lamp actions 일부 easeOut .25/.3 | `RootView.swift:1012`; `StandViewModel.swift:666-720` |
| 홈 단일 탭 mode | 40 steps ×50ms = 2s linear + light impact | `StandViewModel.swift:1294-1319` |
| brightness 100% object lock | 1s delay + medium impact | `StandViewModel.swift:1321-1334` |
| clock pinch HUD | show easeOut .12; 1.2s delay; hide easeOut .25 | `RootView.swift:799-852` |
| editor enter/save | easeOut .25 | `RootView.swift:651-665` |
| editor center snap/resize/accessibility | selection | `RootView.swift:2932-3049` |
| radio/weather merge | medium; split light | `RootView.swift:2356-2379,2440-2487` |
| Settings theme | easeInOut .25 | `SettingsView.swift:142` |
| Settings radio inline open/close | easeInOut .22; save success/error notification | `SettingsView.swift:496-543` |
| Settings font select/reorder | selection | `SettingsView.swift:1365-1369,1801-1809` |
| browser favorites | easeInOut .18; panel move top+opacity | `InternetRadioBrowserView.swift:41-47,191-201` |
| recordings selection/session/merged | easeInOut .22/.24; top move+opacity | `RecordingsView.swift:311-470` |
| weather marquee | 18pt/s, pause 1.2s each end, 30fps | `RootView.swift:1777-1863` |
| 화들짝 lamp | immediate easeOut .3 to max; hold setting; fade sampled 50ms over setting duration | `StandViewModel.swift:649-701` |

## 5. 세로·가로·큰 화면·접근성 배치

### 5.1 orientation과 기본 좌표

- iPhone/iPad app은 portrait, landscapeLeft, landscapeRight만 허용하며 upside-down은 제외; full screen/status hidden/system overlays hidden (`OrientationController` `STandApp.swift:5-30`; `Info.plist:60-81`; `RootView.swift:449`). orientation은 scene geometry update 또는 `setValue` fallback으로 재적용한다.
- orientation 판정은 `height > width`; 정사각형은 landscape 분기다 (`RootView.swift:303-306`). portrait/landscape layout은 독립 저장한다 (`RootView.swift:609-637,658-663`).
- 정확한 기본 `PanelTransform(x,y,scale)`은 다음과 같다. 생략된 scale은 1.0이다 (`StandScreenLayout.portrait/landscape` `STand/Models/AppSettings.swift:273-313`; captured arrangement test `AudioAnalysisTests.swift:728-808`).

| orientation | panel | x | y | scale/group |
|---|---|---:|---:|---|
| portrait | clock | 0 | 0 | 1.2919049397971205 |
| portrait | seconds | 0.33550580431177457 | 0.05785089974293066 | 1 |
| portrait | weather icon/temp/condition 각각 | 0 | -0.20497429305912612 | 0.8692271910752357; group IDs `[1,1,1]` |
| portrait | date | 0 | 0.1179948586118252 | 1 |
| portrait | status(legacy hidden) | 0 | 0.15 | 1 |
| portrait | brightnessRule(legacy hidden) | 0 | 0.21 | 1 |
| portrait | battery | 0 | 0.2069837189374465 | 1 |
| portrait | primary radio | 0 | -0.31070694087403605 | 1.0476520613791829; grouped true |
| portrait | secondary radio | -0.17436152570480928 | 0.31097257926306765 | .75 |
| landscape | clock | 0 | 0.07155322862129146 | 1.2810187063251741 |
| landscape | seconds | 0.2508888888888889 | 0.21401047120418848 | 1 |
| landscape | weather icon/temp/condition 각각 | 0 | -0.25582024432809763 | 0.68640335461830571; group IDs `[1,1,1]` |
| landscape | date | -0.17600000000000007 | -0.08265270506108202 | 1 |
| landscape | status(legacy hidden) | 0 | 0.4646596858638743 | 1 |
| landscape | brightnessRule(legacy hidden) | 0 | 0.32 | 1 |
| landscape | battery | 0 | 0.29780104712041866 | 1 |
| landscape | primary radio | 0.4084444444444445 | -0.2762739965095986 | .75; grouped false |
| landscape | secondary radio | -0.40577777777777785 | -0.27627399650959866 | .75 |

두 orientation의 control order는 `[recordings, settings]`이다. legacy radio fallback transform은 primary `(0.26,0.215,.75)`, secondary `(-0.26,0.215,.75)` (`STand/Models/AppSettings.swift:181-191`).
- 홈 horizontal padding 20/32, editor outer 18/14, font palette max width/height portrait 390×190/landscape650×126 (`RootView.swift:303-365,2239-2247,2508-2527`).
- Settings는 720pt에서 1→2 columns (`SettingsView.swift:58-73`). Recordings는 `ViewThatFits`와 accessibility Dynamic Type에 따라 today row를 수직 전환 (`RecordingsView.swift:265-309`). Browser address bar는 scaled body metric을 44...56 clamp (`InternetRadioBrowserView.swift:15-21`).

### 5.2 접근성

- 모든 명시 label/value/hint/custom action은 화면 표에 포함했다. 원문 위치: 홈 `RootView.swift:361-363,757-783,870-871,1197,1471-1480,1562-1577,1819-1820,2015-2023,2866-3050,3311-3388`; 설정 `SettingsView.swift:342-474,711-776,805-930,1045-1080,1354-1442,1547-1957`; 녹음 `RecordingsView.swift:262,308,649-790,951-1113`; browser `InternetRadioBrowserView.swift:133-203,306-401`; share/widget UIKit/native labels `ShareViewController.swift:16-102`, `STandWidget.swift:22-62`.
- `RootView`의 face-down silhouette는 hit testing 및 accessibility hidden; black cover hit testing false (`RootView.swift:598-602,413-419`). brightness/volume HUD accessibility hidden (`367-371`); clock HUD combined but hit testing false (`1104-1122`).
- 최소 44pt target은 browser, editor, recording controls에서 명시된다. 일반 Settings native Toggle/Button는 SwiftUI 기본 target에 의존한다. Android는 48dp를 보장한다.
- XCUITest, VoiceOver 자동화, Dynamic Type screenshot/snapshot이 없다. 따라서 큰 글자 잘림, Switch Control, Reduce Motion/Transparency, Bold Text, high contrast, RTL은 **직접 미확인**이다. Android 체크리스트에서 별도 실기기 확인한다.
- Reduce Motion/Transparency를 읽는 코드가 없으므로 iOS도 명시 애니메이션/material을 그대로 사용한다. Android가 접근성 setting에 맞춰 줄이면 플랫폼 차이로 기록하되 의미와 최종 상태는 유지한다.

## 6. 설정 기본값·저장·마이그레이션·복구

### 6.1 현재 기본값

| key/의미 | 기본값 | 저장/근거 |
|---|---:|---|
| `lampIntensity` | 0.72; 단, 매 앱 돌봄 시작 시 system brightness로 다시 저장 | `AppSettings.swift:316,593-627`; `StandViewModel.swift:516-533` |
| `silhouetteIntensity` | 0.05 | `AppSettings.swift:317` |
| `clockScale` | 1.0059 | `AppSettings.swift:318`; test `AudioAnalysisTests.swift:721-727` |
| `clockFont` | `.tenada` (5번째) | `AppSettings.swift:319`; test `721-727` |
| `displayTheme` | `.color` | `AppSettings.swift:320` |
| portrait/landscape layout | `StandScreenLayout.portrait/.landscape` exact transforms | `AppSettings.swift:181-314,321-322`; test `728-808` |
| `soundThresholdDB` | -36 | `AppSettings.swift:323` |
| `holdDuration` | 5초 | `AppSettings.swift:324`; migration test `1032-1051` |
| `fadeDuration` | 30초 | `AppSettings.swift:325` |
| `automaticDimmingEnabled` | false | `AppSettings.swift:326` |
| `preventAutomaticDimming` | true | `AppSettings.swift:327` |
| `brightnessModeThreshold` | 0.40 | `AppSettings.swift:328`; start also forces .40 |
| `recordingEnabled` | true | `AppSettings.swift:329` |
| `soundSensingEnabled` | true | `AppSettings.swift:330` |
| `torchEnabled` | true | `AppSettings.swift:331`; migration test `1013-1031` |
| `torchIntensity` | 0.25 (현재 runtime torch policy는 이 값을 읽지 않음) | `AppSettings.swift:332`; encoder `593-627` |
| `wakeOnSleepSound` | false (현재 UI/runtime 미사용 legacy field) | `AppSettings.swift:333` |
| `multiStimulusWakeEnabled` | true | `AppSettings.swift:334` |
| `modePreference` | automatic | `AppSettings.swift:335` |
| `cameraAmbientSensingEnabled` | false | `AppSettings.swift:336` |
| `weatherLocationEnabled` | true | `AppSettings.swift:337` |
| radio channels | [] / selected IDs nil; 최대 2 | `AppSettings.swift:338-344,346-591` |
| radio player volume | 1.0, Settings에 encode하지 않음 | `InternetRadioPlayer.swift:53-56` |
| recording playback boost | true(2×) | `RecordingLibrary.swift:750-755,820-824`; test `3057-3061` |

### 6.2 저장 방식

- `SettingsStore`는 `UserDefaults.standard`, key `appSettings`, `JSONEncoder/Decoder`로 `AppSettings` 전체를 저장한다 (`AppSettings.swift:793-868`). `@Published value.didSet`마다 encode한다. 네 migration marker는 초기 migration을 실제 적용할 때만 별도 UserDefaults bool로 저장하고 restore 시에는 바꾸지 않는다. Android는 DataStore/atomic file에서 대응한다.
- unreadable/future/corrupt payload는 launch 때 recommended UI value를 메모리에 쓰되 원본 data를 덮어쓰지 않는다. 사용자가 실제로 value를 변경한 첫 didSet에만 새 payload로 대체한다 (`SettingsStore.init` `AppSettings.swift:793-853`; test `AudioAnalysisTests.swift:1081-1096`).
- legacy orientation/controls/layout/single-radio/theme/font fields의 custom decoder, missing/unknown control repair, stable IDs, one-time defaults migrations는 `AppSettings.swift:356-790`; 관련 tests `AudioAnalysisTests.swift:54-85,198-370,809-1180`. Android 기존 데이터가 없다 해도 fixture migration tests로 동작을 보존한다.
- `restoreRecommendedValues()`는 `value = .recommended`만 실행하여 didSet 저장을 유발한다 (`AppSettings.swift:860-867`). radio channels/layout/theme/font/permission-use flags를 포함하고, migration marker와 OS permission 자체는 reset하지 않는다.
- 공유 import는 app group `group.com.armsone.stand`, key `pendingInternetRadioImport`, latest-wins JSON. read malformed이면 clear; save/cancel 명시 clear (`InternetRadioConfiguration.swift:89-125`; entitlements files).
- 녹음은 Application Support/S.tand/Recordings, `.sleep-sessions-v1.json`, public approved `.m4a`, hidden `.Pending`; `isExcludedFromBackup=true`를 directory에 설정한다 (`RecordingLibrary.swift:193-220`; `AudioCaptureService.swift:203-230`). Android는 no-backup/app-private storage로 대응한다.
- app start library reload는 directory m4a index, sample install once marker, session manifest load/recovery, unassigned association을 수행한다 (`RecordingLibrary.swift:193-297,495-687`).

## 7. 모드·밝기·카메라·움직임·플래시

### 7.1 상태와 전환

- 표시 mode: stand→`오브제 모드`, sleeping→`매이트 모드`; movement-triggered lamp가 off가 아니면 `화들짝 모드`가 우선 (`StandExperienceMode`, `experienceMode` `StandViewModel.swift:131-151,365-368`).
- automatic brightness-only fallback: level≤0.40 Mate, >0.40 Object; forced object/mate ignore signal (`SimplifiedBrightnessModePolicy` `StandViewModel.swift:63-120`; tests `AudioAnalysisTests.swift:610-638,1603-1677,1772-1807`).
- 일반 auto confirmation: Object→Mate 20초, Mate→Object 35초; fresh camera가 Object→Mate를 지시하면 4초; apply 직전에 재판정하고 바뀌면 취소 (`AutomaticModeTransitionPolicy` `StandViewModel.swift:216-260`; scheduler `983-1057`; tests `639-708`).
- camera: dark≤.16, bright≥.28, middle retain current; reading max age60s; measurement minimum1s, sampling45s; automatic+active+Mate+enabled에서만 sample (`StandViewModel.swift:170-214,1119-1175`; tests `1808-1880`).
- camera capture: simulator unavailable; authorized wide-angle, face-down이면 back 아니면 front, VGA 640×480, BGRA, late discard; frame 8 이후, exposure adjusting이면 frame20 전 skip, ≥1s 및 sample≥5 median; 1.5s timeout; luma with ISO/exposure compensation; image/video never saved (`StandViewModel.swift:1416-1628`).

### 7.2 화들짝·센서·torch

- Mate monitoring active이면 `WakeMotionMonitor` userAcceleration magnitude≥.16 또는 rotation≥1.4에서 callback; minor noise ignored; stop generation으로 queued callback reject (`WakeMotionMonitor.swift:4-15,86-131`; tests `AudioAnalysisTests.swift:2167-2209`).
- audio clap/relative rise and movement 모두 `multiStimulusWakeEnabled`가 true인 Mate에서 `wakeForSleepMovement` (`StandViewModel.swift:418-450,724-762`). startle event manifest는 녹음 없어도 생성/종료 (`RecordingLibrary.swift:345-372`; test `3033-3056`).
- lamp maximum=max(.7,current app brightness), hold `holdDuration` default5, fade to base over `fadeDuration` default30 sampled every50ms. 종료 후 lampPhase holding/base이지 off가 아니다 (`StandViewModel.swift:649-701`).
- torch는 movement-triggered Mate + recent dark camera reading만. `torchEnabled=true`면 max1, false면 still 0.1; 즉, UI switch off가 완전 torch off가 아니라 10% 보조광이라는 실제 코드 정책이다 (`SleepMovementLightingPolicy` `StandViewModel.swift:292-317`; `wakeForSleepMovement/syncTorch` `724-762,1337-1361`; tests `1678-1771`). Object/touch-only에서는 0.
- torch busy race 대응으로 150ms 후, 이어 450ms 후 재동기화 (`StandViewModel.swift:743-762`). hardware unavailable/config error는 조용히 no-op (`TorchController` `1630-1677`).
- low battery: unplugged and ≤20%면 session false, radio/audio/motion/camera/torch/idle timer 정리, current session close, banner. 충전 연결만으로 자동 재시작하지 않으며 버튼으로 재시작 (`StandViewModel.swift:19-43,1367-1407`; test `2134-2148`).

## 8. 오디오 감지·녹음·라디오

### 8.1 마이크 감지와 clip writer

- 실행 조건은 app active + night session + Mate + `soundSensingEnabled` + no suspension(recording playback/radio). 움직임 monitor는 Mate이면 suspension과 무관하게 계속 (`SleepCareMonitoringPolicy`/`syncSleepCareMonitoring` `StandViewModel.swift:271-290,397-404,1198-1219`).
- microphone permission states unknown/granted/denied와 UI failure strings는 `AudioCaptureService.swift:5-27,99-196`. simulator는 `시뮬레이터에서는 소리 감지를 사용하지 않습니다.`
- `AVAudioSession`/engine start, tap format, errors, interruption and route change lifecycle는 `AudioCaptureService.startEngine/receive/installAudioObservers` `AudioCaptureService.swift:188-427`. interruption begin stops and remembers restart; end only `.shouldResume` option이면 resume (`AudioInterruptionResumePolicy` `433-441`; test `AudioAnalysisTests.swift:418-431`). oldDeviceUnavailable/recreate reset paths 포함.
- adaptive noise: calibration60s, quietest/loudest threshold -58/-18; uncalibrated margin은 base threshold와 floor에 따라 policy 계산; current bucket 35th percentile, adaptation median, 올라갈 때 rate .12/내려갈 때 .22 (`AdaptiveSoundThresholdPolicy/AdaptiveNoiseFloorTracker` `AudioAnalysis.swift:27-151`; tests `AudioAnalysisTests.swift:1958-2001`). detector defaults: clap peak -18dB, RMS rise6dB, peak rise8dB, refractory1.5s, sound attack .06s (`AudioDetectorConfiguration/AudioEventDetector` `AudioAnalysis.swift:3-15,301-357`; tests `2236-2315`). stop 때 published effective threshold는 -50으로 reset (`AudioCaptureService.swift:157-176`).
- classifier release silence .18s. movement score=`((1.4-duration)/1.4×.35)+(max(0,crest-7)/14×.25)+(ZCR/.28×.2)+(max(0,.5-lowRatio)/.5×.2)` clamp; candidate if duration≤1.5, score≥.55 and >snore. snore score=`min(1,duration/1.2)×.35+lowRatio×.4+max(0,.2-ZCR)/.2×.15+max(0,14-crest)/14×.1`; candidate if duration≥.45, lowRatio≥.45, score≥.58. sleep-talk score and speech gates(duration .70...30, crest≤18, ZCR .025...24, low .18...72, RMS range≥3.5)는 `SleepSoundClassifier.classifyCurrentSound` 수식 그대로이며 score≥.60. keep은 snore/sleep-talk만, movement≥.55는 wake만 (`AudioAnalysis.swift:193-299`; tests `2316-2458`).
- clip defaults: pre-roll .8s, post-roll 1.4s, segment max90s, pending segment max4; input sample rate/channel/common/interleaving 유지, MPEG-4 AAC 48,000bps, `.m4a`; public filename `sleep-sound-yyyyMMdd-HHmmss-SSS-<8hex>.m4a`. hidden `.Pending`에서 승인 후 `moveItem`; writer stop/reject/abort는 pending 전부 제거 (`ClipSegmentRecorder` `AudioCaptureService.swift:525-779`). tests `AudioAnalysisTests.swift:2459-2769`가 boundary padding, rollover, bounded pending, reject/staging/recovery를 검증한다.

### 8.2 라디오 재생

- config validation: trim; URL required; max2048; scheme exactly HTTPS; nonempty host; user/password nil; display name trim prefix30, empty→`인터넷 라디오`; stable UUID (`InternetRadioConfiguration.swift:3-86`; tests `AudioAnalysisTests.swift:86-122`).
- max channels=2, order first two home panels. selected primary/secondary legacy IDs는 decoder가 repair하며 current `homeInternetRadios`는 ordered first two를 사용한다 (`AppSettings.swift:346-591`; tests `198-370,855-888`).
- player states idle/loading/playing/reconnecting(message)/failed(message), active channel/URL; new AVPlayer receives current nonpersistent volume, play immediately (`InternetRadioPlayer.swift:5-21,53-132`).
- loading timeout30s; playback paused failure delayed path; failure/ended/media reset reconnect. delays [2,4,8,15,30], maximum attempts5 (`InternetRadioPlayer.swift:22-34,148-321`; test `AudioAnalysisTests.swift:371-381`).
- route oldDeviceUnavailable fails and stops; media services reset reconnects. interruption begins player teardown but keeps monitoring suspended; end only OS `.shouldResume` then reconnect, otherwise failed and monitoring resumes (`InternetRadioPlayer.swift:230-349`; interruption policy test `418-431`).
- user stop/channel switch/delete/url change cancels tasks/player/audio session; name-only update does not stop. inactivity callback removes monitoring suspension (`InternetRadioPlayer.swift:135-146,312-367`; `InternetRadioPlaybackMutationPolicy` `StandViewModel.swift:319-342`; tests `460-528`).
- app inactive/background always stops radio (`StandViewModel.appWillResignActive` `615-643`). 라디오 재생 중 audio capture stops but motion continues (`977-981,1198-1219`).

## 9. 날씨·위치

- 상태 idle/requestingLocation/loading/available/locationDenied/failed, published weather/locationName/lastUpdated; desired accuracy는 3km (`WeatherService.swift:43-82`). setting enabled false clears all and cancels; true begins manager flow (`84-123`).
- lastUpdated가 30분 미만이면 non-force refresh skip. 새 location load는 이전 Task cancel, locationName만 즉시 nil; 성공 시 weather/now/available 후 reverse geocode; fetch 실패는 availability failed지만 이전 weather/lastUpdated는 유지 (`WeatherService.refreshIfNeeded/loadWeather` `84-162`). Task cancellation guard가 오래된 response overwrite를 막는다.
- Open-Meteo HTTPS `/v1/forecast`, lat/lon 4 decimals, current temperature/apparent/precip/weather_code/is_day, timezone auto, forecast_days1 (`WeatherService.swift:163-202`). reverse geocode ko_KR, locality/subLocality/admin/country dedupe rules `203-235`; tests `AudioAnalysisTests.swift:2002-2069`.
- WMO Korean summary/SF Symbol map 전체 case는 `CurrentWeather.summary/systemImage` `WeatherService.swift:4-41`; Android strings/icons를 동일 mapping한다.
- location delegate permission/updates/error 모든 분기는 `WeatherService.swift:236-294`. Info usage copy는 `Info.plist:46-47`.

## 10. 녹음 세션·파일 복구·병합

- actual Mate intervals produce manifest sessions; re-enter within30min resumes same session, after split. empty expired sessions cleanup; app background closes current. legacy unassigned clips infer groups when gap from previous clip end≤90min and pad timeline±15min (`SleepSessionGroupingPolicy` `RecordingLibrary.swift:91-162`; session methods `298-383`; tests `2773-3032`).
- filename timestamp parsing, clip duration/resource timestamp, exact association tolerance ±5s, abnormal open-session recovery는 `RecordingLibrary.swift:543-687`; tests `2925-2985`.
- merge requires ≥2 available originals, chronological; exact AVMutableComposition/export behavior and errors `RecordingLibrary.swift:164-191,450-493,688-749`; filenames `today/selected-merged`, merged titles lines20-29. test `3084-3210`.
- deletion is honest partial-success: successful files/references removed even when later error; reload. exact single/batch/all paths `RecordingLibrary.swift:384-449`; tests `2832-2955,3062-3083`.
- `RecordingPlayer` AVAudioEngine/node/mixer uses playback session, 2× is volume gain not speed; seek/progress/schedule completion exact behavior `RecordingLibrary.swift:750-913`.

## 11. 앱 수명주기·background·interruptions

| event | exact behavior | 근거 |
|---|---|---|
| initial Root appear | transient HUD reset, app active handling, start night session, didInitialize true | `RootView.swift:491-496` |
| scene active | transient reset, shared import, brightness restore/adopt, battery check, orientation reapply, if session: idle timer off prevention, posture/audio/weather/camera resume, controls visible | `RootView.swift:497-510`; `StandViewModel.swift:574-613` |
| inactive/background | transient HUD reset, didInitialize false; radio stop; idle timer enable; posture/face-down/torch/camera tasks stop; if session audio/motion stop, startle/session close; night session boolean remains true for resume | `RootView.swift:497-510`; `StandViewModel.swift:615-643` |
| browser inactive/active | page media pause/resume separately | `InternetRadioBrowserView.swift:56-62` |
| recording playback sheet | entering adds suspension, stops radio/audio; dismiss removes suspension and Mate monitoring resumes | `StandViewModel.swift:813-824` |
| audio capture interruption | begin stop; resume only OS option; route/media changes restart or fail | `AudioCaptureService.swift:327-427` |
| radio interruption | teardown, retain suspension; resume only OS option, otherwise fail and release suspension | `InternetRadioPlayer.swift:230-349` |
| low battery | full session stop and requires explicit start | `StandViewModel.swift:1382-1407`; banner `RootView.swift:982-993` |
| face down | app view black/lamp 0 only; system brightness untouched; face up restore | `StandViewModel.swift:1221-1236` |

`UIBackgroundModes`가 Info.plist에 없으므로 background audio/recording을 주장하거나 Android foreground service로 확장하면 parity가 아니다 (`Info.plist:1-83`).

## 12. 권한·개인정보·보안

- OS usage strings: microphone/camera/motion/location exact Korean copy `Info.plist:40-47`. Android manifest/runtime rationale도 의미를 동일하게 유지한다.
- iOS app group은 share only. Privacy manifest: tracking false/domains empty/collected data empty; accessed API reasons UserDefaults CA92.1+1C8F.1, system boot 35F9.1, file timestamp C617.1 (`PrivacyInfo.xcprivacy:5-39`).
- Share extension도 tracking false/collected empty이며 UserDefaults reason 1C8F.1만 선언하고 같은 app group entitlement를 사용한다 (`STandRadioShare/PrivacyInfo.xcprivacy:5-22`; `STandRadioShare/STandRadioShare.entitlements:5-8`). Widget extension은 WidgetKit extension point 외 별도 permission을 선언하지 않는다 (`STandWidget/Info.plist:23-27`).
- no account/analytics/ads/server upload. Recording is app-private/no-backup. Browser is nonpersistent and must not analyze network/audio/HLS/ICY/DOM to auto-discover streams (`InternetRadioBrowserView.swift:6-7,427-455`; explanatory UI strings).
- browser rejects HTTP, credentials, custom/file/blob URLs, download, attachment, unsupported MIME; file upload and web camera/mic/motion denied; TLS trust default only (`InternetRadioBrowserView.swift:560-622,773-933,967-1051`). Android release WebView debugging/cleartext/file access/content access must be disabled.
- shared/browser/user URL and stored payload are untrusted and revalidated. browser never populates channel editor automatically; only explicit OS PasteButton does.

## 13. 예외·실패 처리 완전 목록

| 실패/경계 | 결과 | 근거/테스트 |
|---|---|---|
| invalid radio name/URL | localized inline validation, no save; name empty defaults; overlong name truncates30 rather than fails | `InternetRadioConfiguration.swift:3-67`; test `AudioAnalysisTests.swift:86-122` |
| channel >2 | settings mutation caps/ignores extra according to helper; add UI hidden at2 | `AppSettings.swift:346-730`; test `334-370` |
| active channel removed/URL changed | radio stop; name-only update continues | `StandViewModel.swift:319-342,839-925`; test `460-528` |
| radio network/loading/paused/end/media reset | capped reconnect then failed message; user stop cancels | `InternetRadioPlayer.swift:148-321`; test `371-381` |
| output route removed | immediate failed stop; monitoring suspension released | `InternetRadioPlayer.swift:246-258,312-321` |
| radio interruption no shouldResume | failed `오디오 중단 후...`, monitoring resumes | `InternetRadioPlayer.swift:324-349`; policy test `418-431` |
| browser empty/long/unsafe address | exact B2 error, current page remains | `InternetRadioBrowserView.swift:666-684,967-1051`; test `123-171` |
| browser download/attachment/MIME/process failure | navigation cancel and exact B2 message; refresh offered as toolbar | `InternetRadioBrowserView.swift:773-865` |
| browser clipboard empty | `복사한 웹 주소가 없습니다.` | `InternetRadioBrowserView.swift:290-304` |
| microphone denied/unknown/simulator/start failure | failed state/status; denied routes to Settings; other app features continue | `AudioCaptureService.swift:99-203,428-441`; `SettingsView.swift:619-660,711-776` |
| writer start/write/final move fail | staged audio discarded/partial cleanup; banner `녹음 파일을 ...`; never expose unapproved file | `AudioCaptureService.swift:525-779`; tests `2459-2769` |
| camera denied/unavailable/busy/timeout | state text/fallback brightness signal; no photo; other features continue | `StandViewModel.swift:1416-1628`; policy tests `1808-1880` |
| torch absent/busy/config error | silently remains off; retries for movement | `StandViewModel.swift:743-762,1630-1677` |
| location denied | clear/current state `locationDenied`, panel prompts permission; denied switch opens OS Settings | `WeatherService.swift:84-162,236-294`; `SettingsView.swift:628-669` |
| weather network/decode/geocode failure | `failed`/fallback UI; clock remains | `WeatherService.swift:125-294`; tests `2002-2069` |
| corrupt settings | do not overwrite raw until user mutation | `AppSettings.swift:793-868`; test `1081-1096` |
| malformed shared import | discard/clear; existing channels unchanged | `InternetRadioConfiguration.swift:89-153`; tests `529-609` |
| recording merge <2/no audio/export/delete partial | A3 localized error; actual successes reload | `RecordingLibrary.swift:164-191,384-493`; tests `3062-3210` |
| abnormal app termination/open session | recovery closes without using last clip as false mode-exit; exact association | `RecordingLibrary.swift:579-640`; tests `2925-2985` |
| low battery unplugged≤20% | stop and require explicit start; charge banner | `StandViewModel.swift:1382-1407`; test `2134-2148` |
| queued motion after stop | generation check drops | `WakeMotionMonitor.swift:28-83`; test `2196-2214` |

## 14. 문서·코드 충돌과 dead/legacy 경로

| 충돌 | 실제 코드 판정 | 근거 |
|---|---|---|
| 기존 handoff는 0.24.0이며 홈 세로 drag만 기술 | 0.24.1은 최초 우세축을 고정해 가로 drag radio volume 추가 | `RootView.swift:667-716`; `InternetRadioPlayer.swift:35-56,103-132`; test `AudioAnalysisTests.swift:382-417` |
| 기존 문서 “100% 또는 0% 끝단 1초 유지하면 해당 모드 잠금” | 실제 code는 100%에서만 delayed object lock; 0% Mate는 drag 중 즉시 preference mate이며 별도 1초 task 없음 | `StandViewModel.swift:95-104,1256-1334` |
| 기존 문서 “홈 tap이 현재 lamp phase 따라 dim/brighten” 또는 `ScreenTapPolicy` test | 실제 exposed `handleScreenTap`은 object/mate brightness target 전환. `ScreenTapPolicy`, `HoldDurationAdjustment`, `HoldDurationFeedbackView`는 현재 UI에서 호출되지 않는 legacy/dead symbols | definitions `RootView.swift:40-57,1125-1155`; actual `718-755`; `rg` 호출 결과 test 외 없음 |
| 설정 안내 `시계를 더블 터치하면 테마` | actual Root gesture는 전체 root content shape에 붙어 있어 라디오 high-priority child 등을 제외한 일반 홈 전체에서 double tap | `SettingsView.swift:153-156`; `RootView.swift:445-448,718-749` |
| R1 row accessibility hint “두 번 탭하여 홈 채널로 선택” | 0.25.0에서 실제 동작에 맞게 selected=`현재 홈에 표시되는 채널입니다`, other=`편집에서 순서를 바꾸면 홈에 표시할 수 있습니다`로 수정 | `SettingsView.channelRow` |
| 기존 handoff “R1 삭제는 즉시” | 0.25.0부터 R0/R1/R2/S0 inline의 destructive delete가 모두 confirmation을 거친다 | `SettingsView.pendingDeletion/confirmationDialog`; `RootView` editor confirmation |
| torch off 문구 `사용하지 않음` | 실제 movement-dark Mate policy는 off일 때도 10% torch | `SettingsView.swift:190-198`; `SleepMovementLightingPolicy` `StandViewModel.swift:292-301` |
| `torchIntensity=.25`, `wakeOnSleepSound=false`, `preventAutomaticDimming`, `automaticDimmingEnabled`, legacy brightness controls | stored/decoded fields·policy tests가 남아 있으나 current simplified visible home path에서 일부 미사용/강제 reset. Android는 migration compatibility로 보존하되 노출하지 않는다 | `AppSettings.swift:316-344,593-790`; `RootView.swift:891-928,1928-2147`; `StandViewModel.startNightSession` `516-533` |
| `WeatherBadge`, `HoldDurationFeedbackView`, `NightClock`, `SettingsSliderRow`, `SettingsBrightnessRuleControl` | definitions exist but current visible tree has no call sites. Dashboard uses piece panels; settings uses switches/cards. Android에 이 UI를 노출하지 않는다 | `RootView.swift:1125-1254,1282-1407,3079-3142`; `SettingsView.swift:1045-1082,1181-1329`; repository call-site search |
| `CompactBrightnessRuleControl` | `bottomControl(.brightness)`에 call site가 있지만 `visibleControlOrder`가 `.brightness/.flashlight`를 항상 filter해 현재 도달 불가 | `RootView.swift:891-928,1928-2147`; test `AudioAnalysisTests.swift:1470-1613,1949-1957` |
| silhouette dashboard battery panel·숨김 controls reveal | `isDisplayDark`는 active+lamp off+controls hidden을 요구하지만 current code에서 `controlsVisible`을 false로 쓰는 assignment가 없고 모든 assignment가 true다. 따라서 silhouette와 80pt reveal branch는 현재 일반 실행에서 도달 불가; top battery pill은 계속 current visible battery UI | `StandViewModel.isDisplayDark` `StandViewModel.swift:346-372`; `controlsVisible` writes `522,541,562,607,1363-1365,1403,1409-1413`; UI branches `RootView.swift:313-337,598-602,856-888` |
| Root code has `.stopNightSession` but no visible stop button | current UI only start path; stop is lifecycle/low battery/internal, not user button | `StandViewModel.swift:549-572`; `RootView.centerContent/bottomControl` |

Android는 dead/legacy UI를 새로 노출하지 않는다. 단, 저장 payload migration과 현재 tests가 검증하는 policy는 호환층으로 유지한다.

## 15. Android 플랫폼 차이 — 제외가 아니라 대응

| iOS 기능 | Android 대응 | 허용 차이/금지 |
|---|---|---|
| SwiftUI sheet/fullScreenCover/NavigationStack | Compose ModalBottomSheet/Dialog/NavHost/전체 화면 Activity 또는 destination | 시스템 모양 차이는 허용, 진입·초안·dismiss·confirmation 의미 생략 금지 |
| AVAudioSession/AVPlayer | AudioManager audio focus + ExoPlayer/Media3 | focus interruption resume only system permitted; app background stop; system volume 변경 금지 |
| AVAudioEngine capture | AudioRecord/AAudio + 동일 detector/segmenter | foreground only; foreground service로 기능 확장 금지; codec/container 동등성 검증 |
| CoreMotion posture/movement | SensorManager accelerometer/gyroscope | same thresholds/hysteresis/generation stale callback reject |
| AVCapture camera brightness/torch | CameraX/Camera2 image analysis + torch | no frame 저장/전송; 1s/45s/60s/hysteresis semantics; hardware error fallback |
| CLLocation approximate | coarse location permission/Fused Location | precise 강제 금지; disabled cache clear |
| WKWebView ephemeral | Android WebView isolated/cleared data profile | HTTPS only, uploads/downloads/permissions deny, same-WebView popup, no stream sniffing |
| PasteButton | explicit clipboard paste button | Android clipboard privacy behavior 기록; background clipboard access 금지 |
| Safari Share Extension | `ACTION_SEND text/plain` URL one item receiver | validate again, latest draft, explicit save; broad ACTION_VIEW browser role 금지 |
| WidgetKit accessoryCircular/deep link | lockscreen/home widget shortcut if OEM/API supports; app shortcut fallback | unsupported lockscreen family는 platform difference 기록, app open entry는 제공 |
| SF Symbols/material/haptic | closest Material vector/custom asset, blur fallback, HapticFeedback/Vibrator | icon meaning/size/opacity 유지; blur unavailable 시 measured translucent gradient, 기능 생략 금지 |
| iOS UserDefaults/app group | Preferences DataStore + private share receiver store | unreadable payload preservation and atomic update required |
| no-backup Application Support | `noBackupFilesDir`/`android:allowBackup=false` scoped policy | recordings/settings cloud backup 금지 |

## 16. XCTest 근거 지도와 미검증 항목

`STandTests/AudioAnalysisTests.swift`의 최신 130개 tests는 다음을 검증한다.

- visual resource/policies: burn-in, seconds visibility, bundled fonts/licenses/samples (`8-53`).
- settings/radio/browser/share: legacy decode, URL security, favorites, roundtrip/mutation/max2/reconnect/volume/interruption/panel grouping/share import (`54-609`).
- modes/layout/editor: naming, forced/camera transition, torch, defaults, exact layouts/control rows/migrations/unreadable payload/themes, merge/snap/resize/boundaries (`610-1469`).
- brightness/control/mode/camera: track/tap/typography/opacity, monitoring/torch, simplified drag/system sync (`1470-1957`). 일부는 current hidden legacy controls를 test한다.
- audio/weather/battery/motion: adaptive noise, Open-Meteo/location/marquee/panel geometry, low battery, dimming/hold legacy, motion/face-down/stale callbacks (`1958-2214`).
- detector/classifier/recorder: lamp policy legacy, clap/snap/attack, classification, M4A boundaries/rollover/pending/staging (`2215-2772`).
- recording library/player: grouping/resume/delete/recovery/timeline/startle/boost/partial delete/merge (`2773-3210`).
- 최신 추가: 첫 권한 안내 3...7 실행 schedule/reset 2개와 Mate 진입 60초 gate 1개. UI prompt 순서·OS dialog·회전/재실행·실기기 sensor는 여전히 자동 UI test가 아니다.

직접/자동으로 확인되지 않은 항목:

- 모든 SwiftUI/UIKit 화면 pixel rendering, 정확한 hit-test 우선순위, 실제 animation frame/haptic 강도.
- XCUITest가 없으므로 navigation, popup/dialog, gesture recognizer 경쟁, rotation state preservation, large-screen/large-text clipping.
- VoiceOver 실제 읽기 순서·Rotor/custom action, Switch Control, Reduce Motion/Transparency, Bold Text, high contrast.
- 실제 iPhone/iPad의 camera/torch/microphone/motion/location permission prompt와 denied→Settings→return.
- 실제 HTTP/HLS/ICY stream 30초 timeout/5회 reconnect/audio route/interruption; horizontal volume audible result.
- WebView 각 favorite, popup, media pause/resume, file upload/download reject, TLS/auth, process termination.
- 실제 m4a recording quality, long overnight resource/battery/thermal behavior, filesystem permission/failure injection.
- Widget gallery/lockscreen rendering, Safari share extension, `stand://open` cold/warm launch.

이 미검증 항목은 두 번째 checklist에서 `[실기기]` 또는 `[UI]`를 체크하기 전까지 완료로 쓰지 않는다.

## 17. 사용자 가시 문구·접근성 문구 소스 표현 전수 원장

이 절의 원문 덤프는 `0f664b2` 조사 당시 누락 방지 자료다. `a97743a`에서 바뀐 권한·홈 안내·설정 Hero·라디오 접근성 문구는 0절과 최신 Swift를 우선하며, 아래의 과거 줄 번호와 삭제된 문자열을 Android 최종 문구로 사용하지 않는다.

아래 원장은 UI/확장/위젯 Swift에서 `Text`, `Button`, `Label`, `TextField`, section/navigation title, Settings row의 title/subtitle, accessibility label/hint/value를 재검색한 결과다. 동적 보간과 여러 줄 생성자는 소스 표현 및 첫 줄을 보존하므로 Android 담당자는 이 원장을 string-resource 추출 diff의 입력으로 사용한다. 앞 절의 의미 표를 대체하지 않으며, 같은 문구가 여러 화면에 있으면 각 call site를 유지한다.

```text
STandWidget/STandWidget.swift:25:            .widgetLabel("S.tand 열기")
STandWidget/STandWidget.swift:46:        .accessibilityLabel("S.tand 열기")
STand/UI/InternetRadioBrowserView.swift:72:            TextField("웹 주소 입력", text: $addressText)
STand/UI/InternetRadioBrowserView.swift:77:                .submitLabel(.go)
STand/UI/InternetRadioBrowserView.swift:97:            .accessibilityLabel("새로고침")
STand/UI/InternetRadioBrowserView.swift:149:        .accessibilityLabel(backOrCloseAccessibilityLabel)
STand/UI/InternetRadioBrowserView.swift:150:        .accessibilityHint(
STand/UI/InternetRadioBrowserView.swift:158:        .accessibilityAction(named: Text("브라우저 닫기")) {
STand/UI/InternetRadioBrowserView.swift:171:        .accessibilityLabel(session.isLoading ? "로딩 중지" : "주소로 이동")
STand/UI/InternetRadioBrowserView.swift:172:        .accessibilityHint("길게 누르면 복사한 주소를 붙여넣고 바로 이동합니다")
STand/UI/InternetRadioBrowserView.swift:176:        .accessibilityAction(named: Text("복사한 주소로 이동")) {
STand/UI/InternetRadioBrowserView.swift:197:            .accessibilityLabel(showsFavorites ? "즐겨찾기 닫기" : "즐겨찾기 열기")
STand/UI/InternetRadioBrowserView.swift:309:                Label("즐겨찾기", systemImage: "star.fill")
STand/UI/InternetRadioBrowserView.swift:322:                .accessibilityLabel("즐겨찾기 닫기")
STand/UI/InternetRadioBrowserView.swift:338:                            Text(favorite.title)
STand/UI/InternetRadioBrowserView.swift:341:                            Text(favorite.url.absoluteString)
STand/UI/InternetRadioBrowserView.swift:356:                .accessibilityLabel("\(favorite.title), \(favorite.url.absoluteString)")
STand/UI/InternetRadioBrowserView.swift:359:            Text("웹사이트만 열며 스트리밍 주소를 자동으로 감지하거나 채널에 입력하지 않습니다.")
STand/UI/InternetRadioBrowserView.swift:379:            Text(message)
STand/UI/InternetRadioBrowserView.swift:389:            .accessibilityLabel("안내 닫기")
STand/UI/InternetRadioBrowserView.swift:937:    let title: String
STand/UI/InternetRadioBrowserView.swift:945:            title: "Google",
STand/UI/InternetRadioBrowserView.swift:950:            title: "한국 라디오",
STand/UI/InternetRadioBrowserView.swift:955:            title: "FMSTREAM",
STand/UI/InternetRadioBrowserView.swift:960:            title: "Radio Browser",
STandRadioShare/ShareViewController.swift:5:    private let addressLabel = UILabel()
STandRadioShare/ShareViewController.swift:6:    private let statusLabel = UILabel()
STandRadioShare/ShareViewController.swift:7:    private let saveButton = UIButton(type: .system)
STandRadioShare/ShareViewController.swift:28:        let titleLabel = UILabel()
STandRadioShare/ShareViewController.swift:41:        let explanationLabel = UILabel()
STandRadioShare/ShareViewController.swift:67:        let cancelButton = UIButton(configuration: cancelConfiguration)
STand/UI/RecordingsView.swift:39:                    ContentUnavailableView(
STand/UI/RecordingsView.swift:42:                        description: Text("매이트 모드에서 코골이와 잠꼬대 후보가 감지되면 필요한 구간만 저장합니다.")
STand/UI/RecordingsView.swift:72:                                Label(mergeStatusMessage, systemImage: "checkmark.circle.fill")
STand/UI/RecordingsView.swift:105:            .navigationTitle("수면 소리")
STand/UI/RecordingsView.swift:112:                    Button("닫기") { dismiss() }
STand/UI/RecordingsView.swift:118:                            Button("전체 선택", systemImage: "checkmark.square.fill") {
STand/UI/RecordingsView.swift:124:                            Button("오늘 선택", systemImage: "calendar.badge.checkmark") {
STand/UI/RecordingsView.swift:130:                            Button("선택 모두 해제", systemImage: "checkmark.circle.badge.xmark") {
STand/UI/RecordingsView.swift:137:                            Button("전체 삭제", systemImage: "trash", role: .destructive) {
STand/UI/RecordingsView.swift:142:                            Label("목록 작업", systemImage: "ellipsis.circle")
STand/UI/RecordingsView.swift:153:                Button("모두 삭제", role: .destructive) {
STand/UI/RecordingsView.swift:164:                Button("취소", role: .cancel) {}
STand/UI/RecordingsView.swift:166:                Text("삭제한 녹음은 복구할 수 없습니다.")
STand/UI/RecordingsView.swift:173:                Button("선택 항목 삭제", role: .destructive) {
STand/UI/RecordingsView.swift:177:                Button("취소", role: .cancel) {}
STand/UI/RecordingsView.swift:179:                Text("삭제한 원본 녹음은 복구할 수 없습니다.")
STand/UI/RecordingsView.swift:186:                Button("합치고 지우기", role: .destructive) {
STand/UI/RecordingsView.swift:189:                Button("취소", role: .cancel) {}
STand/UI/RecordingsView.swift:191:                Text("합본은 남지만 선택한 원본 녹음은 복구할 수 없습니다.")
STand/UI/RecordingsView.swift:202:                    Button("녹음 삭제", role: .destructive) {
STand/UI/RecordingsView.swift:206:                Button("취소", role: .cancel) { pendingClipDeletion = nil }
STand/UI/RecordingsView.swift:208:                Text("삭제한 녹음은 복구할 수 없습니다.")
STand/UI/RecordingsView.swift:217:                Button("확인", role: .cancel) {}
STand/UI/RecordingsView.swift:219:                Text(mergeErrorMessage ?? "알 수 없는 오류가 발생했습니다.")
STand/UI/RecordingsView.swift:243:                Text("기록 요약")
STand/UI/RecordingsView.swift:245:                Text("잠자리 \(library.recordingSessions.count)회 · 원본 \(library.mergeableClips.count)개")
STand/UI/RecordingsView.swift:253:                Text(originalDuration.durationText)
STand/UI/RecordingsView.swift:255:                Text("원본 소리")
STand/UI/RecordingsView.swift:283:            Label("오늘", systemImage: "calendar")
STand/UI/RecordingsView.swift:285:            Text("\(todayClips.count)개 · \(todayClips.reduce(0) { $0 + $1.duration }.durationText)")
STand/UI/RecordingsView.swift:292:        Button(action: mergeTodayRecordings) {
STand/UI/RecordingsView.swift:297:                    Label("오늘 소리 합치기", systemImage: "waveform.path.badge.plus")
STand/UI/RecordingsView.swift:308:        .accessibilityHint("오늘 원본을 시간순으로 합치며 원본은 그대로 둡니다")
STand/UI/RecordingsView.swift:323:                        Text("녹음 고르기")
STand/UI/RecordingsView.swift:325:                        Text(selectedClipURLs.isEmpty ? "합치거나 지울 소리를 선택합니다" : "\(selectedClipURLs.count)개 선택됨")
STand/UI/RecordingsView.swift:344:                    RecordingActionTile(title: "모두 고르기", systemImage: "checkmark.square.fill", accent: accent) {
STand/UI/RecordingsView.swift:348:                    RecordingActionTile(title: "오늘만 고르기", systemImage: "calendar.badge.checkmark", accent: accent) {
STand/UI/RecordingsView.swift:352:                    RecordingActionTile(title: "선택 풀기", systemImage: "xmark.square", accent: accent) {
STand/UI/RecordingsView.swift:358:                Text("소리를 고르면 화면 아래에서 합치거나 삭제할 수 있습니다.")
STand/UI/RecordingsView.swift:365:                    Label("합친 뒤 원본 지우기", systemImage: "waveform.path.badge.minus")
STand/UI/RecordingsView.swift:437:                        Text("한데 묶은 소리")
STand/UI/RecordingsView.swift:439:                        Text("\(mergedClips.count)개 · 원본과 별도로 보관")
STand/UI/RecordingsView.swift:649:        Label(text, systemImage: "info.circle.fill")
STand/UI/RecordingsView.swift:669:            Button(action: clear) {
STand/UI/RecordingsView.swift:675:            .accessibilityLabel("선택 해제")
STand/UI/RecordingsView.swift:677:            Text("\(count)개 선택")
STand/UI/RecordingsView.swift:683:            Button(action: merge) {
STand/UI/RecordingsView.swift:684:                Label("한데 묶기", systemImage: "waveform.path.badge.plus")
STand/UI/RecordingsView.swift:693:            Button(action: delete) {
STand/UI/RecordingsView.swift:701:            .accessibilityLabel("선택 삭제")
STand/UI/RecordingsView.swift:714:    let title: String
STand/UI/RecordingsView.swift:722:        Button(action: action) {
STand/UI/RecordingsView.swift:726:                Text(title)
STand/UI/RecordingsView.swift:751:                        Text(sessionTitle)
STand/UI/RecordingsView.swift:754:                            Text("시간 추정")
STand/UI/RecordingsView.swift:762:                    Text(activitySummary)
STand/UI/RecordingsView.swift:770:                    Text("\(selectedCount) 선택")
STand/UI/RecordingsView.swift:788:        .accessibilityLabel(accessibilityLabel)
STand/UI/RecordingsView.swift:789:        .accessibilityValue(isExpanded ? "녹음 목록 펼쳐짐" : "녹음 목록 접힘")
STand/UI/RecordingsView.swift:790:        .accessibilityHint("두 번 탭하여 녹음 목록을 \(isExpanded ? "접습니다" : "펼칩니다")")
STand/UI/RecordingsView.swift:891:                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
STand/UI/RecordingsView.swift:893:                Text("수면 소리 · 얇은 선은 화들짝")
STand/UI/RecordingsView.swift:895:                Text(session.endedAt.formatted(date: .omitted, time: .shortened))
STand/UI/RecordingsView.swift:969:                    .accessibilityLabel("합친 녹음")
STand/UI/RecordingsView.swift:971:                Button(action: toggleSelection) {
STand/UI/RecordingsView.swift:979:                .accessibilityLabel(isSelected ? "녹음 선택 해제" : "녹음 선택")
STand/UI/RecordingsView.swift:982:            Button(action: play) {
STand/UI/RecordingsView.swift:991:            .accessibilityLabel(isPlaying ? "재생 일시 정지" : isActive ? "재생 계속" : "녹음 재생")
STand/UI/RecordingsView.swift:993:            Button(action: play) {
STand/UI/RecordingsView.swift:1000:            .accessibilityLabel("\(clip.mergedTitle ?? "수면 소리") 재생")
STand/UI/RecordingsView.swift:1004:                    Label("공유", systemImage: "square.and.arrow.up")
STand/UI/RecordingsView.swift:1006:                Button("삭제", systemImage: "trash", role: .destructive, action: delete)
STand/UI/RecordingsView.swift:1013:            .accessibilityLabel("녹음 작업")
STand/UI/RecordingsView.swift:1026:            Text(rowTitle)
STand/UI/RecordingsView.swift:1031:                Text(clip.duration.durationText)
STand/UI/RecordingsView.swift:1032:                if clip.isMerged { Text("합본") }
STand/UI/RecordingsView.swift:1065:                .accessibilityLabel(player.isPlaying ? "재생 일시 정지" : "재생 계속")
STand/UI/RecordingsView.swift:1073:                        Text("2×")
STand/UI/RecordingsView.swift:1084:                .accessibilityLabel(player.boostEnabled ? "작은 소리 두 배 증폭 끄기" : "작은 소리 두 배 증폭 켜기")
STand/UI/RecordingsView.swift:1097:                        Text(player.currentTime.durationText)
STand/UI/RecordingsView.swift:1099:                        Text(player.duration.durationText)
STand/UI/RecordingsView.swift:1113:                .accessibilityLabel("재생 닫기")
STand/UI/SettingsView.swift:78:            .navigationTitle("설정")
STand/UI/SettingsView.swift:85:                    Button("완료") { dismiss() }
STand/UI/SettingsView.swift:114:                Button("채널 삭제", role: .destructive) {
STand/UI/SettingsView.swift:122:            Button("취소", role: .cancel) { pendingRadioDeletion = nil }
STand/UI/SettingsView.swift:124:            Text("삭제한 채널 주소는 되돌릴 수 없습니다.")
STand/UI/SettingsView.swift:131:            Button("추천 설정 복원", role: .destructive) {
STand/UI/SettingsView.swift:134:            Button("취소", role: .cancel) {}
STand/UI/SettingsView.swift:136:            Text("저장한 라디오 채널을 포함해 앱 설정이 처음 모습으로 돌아갑니다.")
STand/UI/SettingsView.swift:146:        StandSettingsCard(
STand/UI/SettingsView.swift:147:            title: "화면과 시계",
STand/UI/SettingsView.swift:148:            subtitle: "테마와 시계 글꼴을 바꿉니다",
STand/UI/SettingsView.swift:153:                SettingsFieldLabel("테마")
STand/UI/SettingsView.swift:154:                Text("시계를 더블 터치하면 테마가 바뀝니다.")
STand/UI/SettingsView.swift:168:                SettingsNavigationRow(
STand/UI/SettingsView.swift:169:                    title: "시계 글꼴",
STand/UI/SettingsView.swift:177:            SettingsHelpText(
STand/UI/SettingsView.swift:184:        StandSettingsCard(
STand/UI/SettingsView.swift:185:            title: "권한 설정",
STand/UI/SettingsView.swift:186:            subtitle: "필요한 기능만 선택해서 사용합니다",
STand/UI/SettingsView.swift:190:            SettingsToggleRow(
STand/UI/SettingsView.swift:191:                title: "플래시 사용",
STand/UI/SettingsView.swift:192:                subtitle: store.value.torchEnabled
STand/UI/SettingsView.swift:200:            SettingsToggleRow(
STand/UI/SettingsView.swift:201:                title: "카메라 사용",
STand/UI/SettingsView.swift:202:                subtitle: cameraAmbientStatusText,
STand/UI/SettingsView.swift:216:            SettingsToggleRow(
STand/UI/SettingsView.swift:217:                title: "마이크 사용",
STand/UI/SettingsView.swift:218:                subtitle: microphonePermissionText,
STand/UI/SettingsView.swift:230:            SettingsToggleRow(
STand/UI/SettingsView.swift:231:                title: "위치 정보 사용",
STand/UI/SettingsView.swift:232:                subtitle: locationPermissionText,
STand/UI/SettingsView.swift:247:        StandSettingsCard(
STand/UI/SettingsView.swift:248:            title: "잠꼬대와 코골이",
STand/UI/SettingsView.swift:249:            subtitle: "매이트 모드에서만 작동합니다",
STand/UI/SettingsView.swift:263:            SettingsToggleRow(
STand/UI/SettingsView.swift:264:                title: "다시 밝혀주기",
STand/UI/SettingsView.swift:265:                subtitle: "박수, 핑거스냅, 뒤척임과 기기 움직임에 반응",
STand/UI/SettingsView.swift:271:            SettingsToggleRow(
STand/UI/SettingsView.swift:272:                title: "코골이·잠꼬대 저장",
STand/UI/SettingsView.swift:273:                subtitle: "후보 소리가 날 때 필요한 구간만 저장",
STand/UI/SettingsView.swift:279:            SettingsInlineButton(
STand/UI/SettingsView.swift:280:                title: library.clips.isEmpty ? "수면 소리 열기" : "녹음 \(library.clips.count)개 보기",
STand/UI/SettingsView.swift:288:            SettingsHelpText(
STand/UI/SettingsView.swift:297:        return StandSettingsCard(
STand/UI/SettingsView.swift:298:            title: "인터넷 라디오",
STand/UI/SettingsView.swift:299:            subtitle: channels.isEmpty
STand/UI/SettingsView.swift:306:                Label("등록한 채널이 없습니다", systemImage: "radio")
STand/UI/SettingsView.swift:327:                    SettingsInlineButton(
STand/UI/SettingsView.swift:328:                        title: channels.isEmpty ? "첫 채널 추가" : "채널 추가",
STand/UI/SettingsView.swift:336:            SettingsHelpText(
STand/UI/SettingsView.swift:359:                        Text(channel.displayName)
STand/UI/SettingsView.swift:362:                        Text(radioStatusText(isActive: isActive))
STand/UI/SettingsView.swift:372:            .accessibilityLabel("\(channel.displayName), \(radioStatusText(isActive: isActive))")
STand/UI/SettingsView.swift:373:            .accessibilityHint(isActive ? "라디오를 정지합니다" : "라디오를 재생합니다")
STand/UI/SettingsView.swift:384:            .accessibilityLabel("\(channel.displayName) 수정")
STand/UI/SettingsView.swift:401:                Label(
STand/UI/SettingsView.swift:407:                Button("닫기", action: closeInlineRadioEditor)
STand/UI/SettingsView.swift:412:            TextField("이름 (선택)", text: $radioDraftName)
STand/UI/SettingsView.swift:417:            TextField("https://…", text: $radioDraftAddress, axis: .vertical)
STand/UI/SettingsView.swift:427:                Label(radioValidationMessage, systemImage: "exclamationmark.triangle.fill")
STand/UI/SettingsView.swift:433:                PasteButton(payloadType: String.self) { values in
STand/UI/SettingsView.swift:443:                    Label("웹에서 찾기", systemImage: "safari.fill")
STand/UI/SettingsView.swift:451:                    Button(role: .destructive) {
STand/UI/SettingsView.swift:458:                    .accessibilityLabel("\(editingRadioChannel.displayName) 삭제")
STand/UI/SettingsView.swift:461:                Button(action: saveInlineRadioChannel) {
STand/UI/SettingsView.swift:462:                    Label("저장", systemImage: "checkmark.circle.fill")
STand/UI/SettingsView.swift:485:    private func radioStatusText(isActive: Bool) -> String {
STand/UI/SettingsView.swift:547:        StandSettingsCard(
STand/UI/SettingsView.swift:548:            title: "정보",
STand/UI/SettingsView.swift:549:            subtitle: "개인정보, 저작권과 앱 정보를 확인합니다",
STand/UI/SettingsView.swift:553:            SettingsInfoRow(
STand/UI/SettingsView.swift:554:                title: "버전",
STand/UI/SettingsView.swift:563:                SettingsNavigationRow(
STand/UI/SettingsView.swift:564:                    title: "내장 폰트 저작권",
STand/UI/SettingsView.swift:573:                SettingsNavigationRow(
STand/UI/SettingsView.swift:574:                    title: "날씨 데이터",
STand/UI/SettingsView.swift:583:                Label("오디오는 이 기기에서 처리하고 로컬에만 저장합니다.", systemImage: "lock.shield.fill")
STand/UI/SettingsView.swift:584:                Label("함께 있는 사람에게 녹음 사실을 먼저 알려 주세요.", systemImage: "person.2.fill")
STand/UI/SettingsView.swift:585:                Label("충전 중인 기기와 플래시를 침구로 덮지 마세요.", systemImage: "thermometer.medium")
STand/UI/SettingsView.swift:590:            Button(role: .destructive) {
STand/UI/SettingsView.swift:593:                Label("추천 설정 복원", systemImage: "arrow.counterclockwise")
STand/UI/SettingsView.swift:723:                    Text(statusTitle)
STand/UI/SettingsView.swift:725:                    Text(statusDetail)
STand/UI/SettingsView.swift:734:                SettingsInlineButton(
STand/UI/SettingsView.swift:735:                    title: "마이크 권한 열기",
STand/UI/SettingsView.swift:816:                Text("S.tand")
STand/UI/SettingsView.swift:818:                Text("낮에는 오브제\n밤에는 매이트")
STand/UI/SettingsView.swift:826:            Button(action: onToggleMode) {
STand/UI/SettingsView.swift:828:                    title: isNightSessionActive ? environmentText : "S.tand 멈춤",
STand/UI/SettingsView.swift:838:            .accessibilityHint("홈 화면을 한 번 누른 것처럼 오브제와 매이트 모드를 전환합니다")
STand/UI/SettingsView.swift:864:    let title: String
STand/UI/SettingsView.swift:870:        Label(title, systemImage: systemImage)
STand/UI/SettingsView.swift:912:                        Text(theme.title)
STand/UI/SettingsView.swift:925:                .accessibilityLabel("\(theme.title) 테마")
STand/UI/SettingsView.swift:933:    let title: String
STand/UI/SettingsView.swift:934:    let subtitle: String
STand/UI/SettingsView.swift:940:        title: String,
STand/UI/SettingsView.swift:941:        subtitle: String,
STand/UI/SettingsView.swift:963:                    Text(title)
STand/UI/SettingsView.swift:965:                    Text(subtitle)
STand/UI/SettingsView.swift:1001:    let title: String
STand/UI/SettingsView.swift:1003:    init(_ title: String) {
STand/UI/SettingsView.swift:1008:        Text(title)
STand/UI/SettingsView.swift:1016:    let title: String
STand/UI/SettingsView.swift:1017:    let subtitle: String
STand/UI/SettingsView.swift:1031:                    Text(title)
STand/UI/SettingsView.swift:1033:                    Text(subtitle)
STand/UI/SettingsView.swift:1046:    let title: String
STand/UI/SettingsView.swift:1058:                Text(title)
STand/UI/SettingsView.swift:1061:                Text(valueText)
STand/UI/SettingsView.swift:1068:                .accessibilityLabel(title)
STand/UI/SettingsView.swift:1069:                .accessibilityValue(valueText)
STand/UI/SettingsView.swift:1073:                    Text(leadingLabel ?? "")
STand/UI/SettingsView.swift:1075:                    Text(trailingLabel ?? "")
STand/UI/SettingsView.swift:1085:    let title: String
STand/UI/SettingsView.swift:1097:            Text(title)
STand/UI/SettingsView.swift:1100:            Text(value)
STand/UI/SettingsView.swift:1113:    let title: String
STand/UI/SettingsView.swift:1123:            Text(title)
STand/UI/SettingsView.swift:1126:            Text(value)
STand/UI/SettingsView.swift:1135:    let title: String
STand/UI/SettingsView.swift:1140:        Label(title, systemImage: systemImage)
STand/UI/SettingsView.swift:1153:    let title: String
STand/UI/SettingsView.swift:1159:        Button(action: action) {
STand/UI/SettingsView.swift:1160:            SettingsInlineButtonLabel(title: title, systemImage: systemImage, accent: accent)
STand/UI/SettingsView.swift:1174:        Text(text)
STand/UI/SettingsView.swift:1193:                Label("매이트", systemImage: "moon.fill")
STand/UI/SettingsView.swift:1196:                Text("밝기 기준")
STand/UI/SettingsView.swift:1199:                Label("오브제", systemImage: "sun.max.fill")
STand/UI/SettingsView.swift:1239:            Text("현재 \(Int((currentBrightness * 100).rounded()))% · 기준 \(Int((threshold * 100).rounded()))% · \(modeText)")
STand/UI/SettingsView.swift:1250:        .accessibilityLabel("밝기 기준")
STand/UI/SettingsView.swift:1251:        .accessibilityValue("현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트, \(modeText)")
STand/UI/SettingsView.swift:1252:        .accessibilityHint("좌우로 밀어 조절하거나 탭하여 매이트와 오브제를 전환합니다")
STand/UI/SettingsView.swift:1350:        .accessibilityLabel("감지 레벨 \(Int(level * 100))퍼센트")
STand/UI/SettingsView.swift:1382:        .navigationTitle("시계 글꼴")
STand/UI/SettingsView.swift:1412:                Text("12:34")
STand/UI/SettingsView.swift:1423:                Text(choice.displayName)
STand/UI/SettingsView.swift:1440:        .accessibilityLabel("\(choice.displayName) 플립시계 미리보기\(selected ? ", 선택됨" : "")")
STand/UI/SettingsView.swift:1462:                Text("S.tand는 시계 표시를 위해 HanClip에서 검증해 보관한 프리텐다드, 카카오 Big Sans, 나눔고딕, 태나다, 검은고딕, 도현, 페이퍼로지 Bold, 넥슨 Lv.1 고딕, Poppins의 원본 서체 파일을 수정하지 않고 포함합니다.")
STand/UI/SettingsView.swift:1463:                Text("프리텐다드, 카카오 Big Sans, 나눔고딕, 태나다, 검은고딕, 도현, 페이퍼로지와 Poppins는 SIL Open Font License 1.1에 따라 앱·소프트웨어 번들 및 임베딩이 허용됩니다. 서체 파일 자체를 단독 판매하지 않으며, 각 저작권 고지와 라이선스 전문을 앱 번들에 함께 보관합니다.")
STand/UI/SettingsView.swift:1464:                Text("페이퍼로지는 제작자의 공식 저장소에서 배포한 1.001 Bold 원본이며, Poppins는 Google Fonts 공식 저장소의 Regular 원본입니다. 넥슨 Lv.1 고딕의 저작권은 NEXON Korea에 있으며 공식 이용 조건에 따라 원본 파일과 저작권 안내를 함께 번들합니다.")
STand/UI/SettingsView.swift:1466:                Text("내장 폰트 저작권")
STand/UI/SettingsView.swift:1469:            Section("라이선스 전문") {
STand/UI/SettingsView.swift:1478:                Text("시스템 둥근체는 iOS 시스템 서체이며 S.tand 앱 번들에 별도 서체 파일로 포함하지 않습니다.")
STand/UI/SettingsView.swift:1485:        .navigationTitle("폰트 저작권")
STand/UI/SettingsView.swift:1498:                Text(licenseText)
STand/UI/SettingsView.swift:1505:        .navigationTitle(font.displayName)
STand/UI/SettingsView.swift:1575:                            Label("저장한 채널이 없습니다", systemImage: "radio")
STand/UI/SettingsView.swift:1577:                            Text("직접 이용할 수 있는 HTTPS 스트림 주소를 추가해 주세요.")
STand/UI/SettingsView.swift:1582:                                Label("첫 채널 추가", systemImage: "plus.circle.fill")
STand/UI/SettingsView.swift:1594:                                    Button(role: .destructive) {
STand/UI/SettingsView.swift:1597:                                        Label("삭제", systemImage: "trash")
STand/UI/SettingsView.swift:1603:                                        Label("수정", systemImage: "pencil")
STand/UI/SettingsView.swift:1610:                        Text("목록의 첫 두 채널이 홈에 표시됩니다")
STand/UI/SettingsView.swift:1612:                        Text("편집을 눌러 순서를 바꾸면 홈 라디오 패널 순서도 함께 바뀝니다.")
STand/UI/SettingsView.swift:1620:                        Label("웹에서 주소 찾기", systemImage: "safari.fill")
STand/UI/SettingsView.swift:1622:                    .accessibilityHint("앱 안의 브라우저에서 주소를 찾고 직접 복사합니다")
STand/UI/SettingsView.swift:1624:                    Text("브라우저는 스트리밍 주소를 자동으로 감지하거나 채널에 입력하지 않습니다. 이용 권한이 있는 주소를 직접 복사한 뒤 채널 추가 화면에서 붙여넣어 주세요.")
STand/UI/SettingsView.swift:1627:                Section("재생 안내") {
STand/UI/SettingsView.swift:1628:                    Label("라디오 재생 중에는 소리 감지와 녹음이 일시 중지됩니다.", systemImage: "waveform.slash")
STand/UI/SettingsView.swift:1629:                    Label("앱이 화면을 떠나면 라디오가 자동으로 멈춥니다.", systemImage: "iphone.slash")
STand/UI/SettingsView.swift:1634:            .navigationTitle("인터넷 라디오")
STand/UI/SettingsView.swift:1641:                    Button("완료") { dismiss() }
STand/UI/SettingsView.swift:1645:                        EditButton()
STand/UI/SettingsView.swift:1651:                            Label("채널 추가", systemImage: "plus")
STand/UI/SettingsView.swift:1653:                        .accessibilityHint("이름과 HTTPS 스트림 주소를 직접 입력합니다")
STand/UI/SettingsView.swift:1696:                        Text(channel.displayName)
STand/UI/SettingsView.swift:1699:                        Text(channelStatus(channel, isActive: isActive))
STand/UI/SettingsView.swift:1710:            .accessibilityLabel(
STand/UI/SettingsView.swift:1711:                channelAccessibilityLabel(
STand/UI/SettingsView.swift (`33711c0`, `channelRow`): selected `현재 홈에 표시되는 채널입니다`; other `편집에서 순서를 바꾸면 홈에 표시할 수 있습니다`
STand/UI/SettingsView.swift:1731:            .accessibilityLabel("\(channel.displayName) 수정")
STand/UI/SettingsView.swift:1737:                Label("채널 수정", systemImage: "pencil")
STand/UI/SettingsView.swift:1739:            Button(role: .destructive) {
STand/UI/SettingsView.swift:1742:                Label("채널 삭제", systemImage: "trash")
STand/UI/SettingsView.swift:1763:    private func channelAccessibilityLabel(
STand/UI/SettingsView.swift:1852:                TextField("이름 (선택)", text: $displayName)
STand/UI/SettingsView.swift:1854:                    .accessibilityHint("비워 두면 인터넷 라디오로 저장됩니다")
STand/UI/SettingsView.swift:1856:                TextField("https://…", text: $address, axis: .vertical)
STand/UI/SettingsView.swift:1864:                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
STand/UI/SettingsView.swift:1867:                        .accessibilityLabel("입력 오류, \(validationMessage)")
STand/UI/SettingsView.swift:1870:                PasteButton(payloadType: String.self) { values in
STand/UI/SettingsView.swift:1875:                .accessibilityLabel("복사한 주소 붙여넣기")
STand/UI/SettingsView.swift:1876:                .accessibilityHint("클립보드의 텍스트를 주소 입력란에 넣습니다")
STand/UI/SettingsView.swift:1878:                Text("채널 정보")
STand/UI/SettingsView.swift:1880:                Text("직접 이용 권한을 확인한 합법적인 HTTPS 스트림 주소만 등록해 주세요. 이름은 최대 30자, 주소는 최대 2,048자로 저장됩니다.")
STand/UI/SettingsView.swift:1887:                    Label("웹에서 주소 찾기", systemImage: "safari.fill")
STand/UI/SettingsView.swift:1889:                .accessibilityHint("브라우저에서 주소를 찾고 직접 복사합니다")
STand/UI/SettingsView.swift:1891:                Text("브라우저에서 이용 권한이 있는 주소를 직접 복사한 뒤 이 화면으로 돌아와 붙여넣어 주세요. 웹페이지 주소는 자동으로 입력되지 않습니다.")
STand/UI/SettingsView.swift:1894:            Section("재생 중 동작") {
STand/UI/SettingsView.swift:1895:                Label("소리 감지와 수면 녹음은 일시 중지됩니다.", systemImage: "waveform.slash")
STand/UI/SettingsView.swift:1896:                Label("기기 움직임 감지는 계속됩니다.", systemImage: "gyroscope")
STand/UI/SettingsView.swift:1901:                    Button("이 채널 삭제", role: .destructive) {
STand/UI/SettingsView.swift:1904:                    .accessibilityHint("확인 후 \(configuration.displayName) 채널을 삭제합니다")
STand/UI/SettingsView.swift:1911:        .navigationTitle(configuration == nil ? "채널 추가" : "채널 수정")
STand/UI/SettingsView.swift:1915:                Button("저장", action: save)
STand/UI/SettingsView.swift:1928:                Button("채널 삭제", role: .destructive) {
STand/UI/SettingsView.swift:1933:            Button("취소", role: .cancel) {}
STand/UI/SettingsView.swift:1935:            Text("삭제한 채널 주소는 되돌릴 수 없습니다.")
STand/UI/RootView.swift:32:        Text(date, format: .dateTime.month().day().weekday(.wide))
STand/UI/RootView.swift:347:                            Text(AppVersion.build)
STand/UI/RootView.swift:348:                            Text("·")
STand/UI/RootView.swift:349:                            Text("밝기 \(Int((model.displayBrightness * 100).rounded()))%")
STand/UI/RootView.swift:361:                    .accessibilityLabel(
STand/UI/RootView.swift:539:                Label(statusTitle, systemImage: statusImage)
STand/UI/RootView.swift:553:                Text("S.tand")
STand/UI/RootView.swift:575:                Text("S.tand가 곁에 있을게요")
STand/UI/RootView.swift:578:                Text("시작하면 오브제와 매이트 모드를 오가며 시간·날씨와 잠자리를 돌봅니다.")
STand/UI/RootView.swift:585:                    Label("S.tand 시작", systemImage: "lamp.table.fill")
STand/UI/RootView.swift:592:                .accessibilityHint("자동 잠금을 막고 소리 감지를 시작합니다")
STand/UI/RootView.swift:761:            .accessibilityLabel("홈 화면 제어")
STand/UI/RootView.swift:762:            .accessibilityValue(
STand/UI/RootView.swift:765:            .accessibilityHint("위아래로 쓸어 앱 밝기를 조절하거나 동작 메뉴에서 모드, 테마와 편집을 선택합니다")
STand/UI/RootView.swift:773:            .accessibilityAction(named: Text("오브제와 매이트 전환"), handleScreenTap)
STand/UI/RootView.swift:774:            .accessibilityAction(named: Text("테마 전환"), toggleDisplayTheme)
STand/UI/RootView.swift:775:            .accessibilityAction(named: Text("화면 편집 열기")) {
STand/UI/RootView.swift:778:            .accessibilityAction(named: Text("시계 크게")) {
STand/UI/RootView.swift:781:            .accessibilityAction(named: Text("시계 작게")) {
STand/UI/RootView.swift:870:            .accessibilityLabel("하단 기능 버튼 열기")
STand/UI/RootView.swift:871:            .accessibilityHint("두 번 누르면 녹음 및 설정 버튼이 나타납니다")
STand/UI/RootView.swift:903:            ControlButton(
STand/UI/RootView.swift:904:                title: "플래시 연동",
STand/UI/RootView.swift:930:            ControlButton(
STand/UI/RootView.swift:931:                title: "녹음 목록 보기",
STand/UI/RootView.swift:941:            ControlButton(
STand/UI/RootView.swift:942:                title: "설정 열기",
STand/UI/RootView.swift:953:        Label(
STand/UI/RootView.swift:969:                Label(message, systemImage: "externaldrive.badge.exclamationmark")
STand/UI/RootView.swift:983:        Label(
STand/UI/RootView.swift:1054:            Text("앱 밝기")
STand/UI/RootView.swift:1057:            Text("\(percent)%")
STand/UI/RootView.swift:1083:            Text("라디오 볼륨")
STand/UI/RootView.swift:1086:            Text("\(percent)%")
STand/UI/RootView.swift:1111:            Text("시계 크기")
STand/UI/RootView.swift:1113:            Text("\(Int((scale * 100).rounded()))%")
STand/UI/RootView.swift:1132:            Text("어두워지기까지")
STand/UI/RootView.swift:1137:            Text(durationText)
STand/UI/RootView.swift:1197:        .accessibilityLabel(accessibilityText)
STand/UI/RootView.swift:1208:            Text(primaryText)
STand/UI/RootView.swift:1211:                Text(secondaryText)
STand/UI/RootView.swift:1332:                    Label(batteryText, systemImage: batterySystemImage)
STand/UI/RootView.swift:1471:        .accessibilityLabel(accessibilityLabel)
STand/UI/RootView.swift:1472:        .accessibilityHint(accessibilityHint)
STand/UI/RootView.swift:1480:        .accessibilityAction(named: Text("채널 편집"), editAction)
STand/UI/RootView.swift:1491:                Text(configuration?.displayName ?? "인터넷 라디오")
STand/UI/RootView.swift:1495:                Text(statusText)
STand/UI/RootView.swift:1730:                WeatherLocationLabel(
STand/UI/RootView.swift:1812:        WeatherLocationMarqueeText(
STand/UI/RootView.swift:1820:        .accessibilityLabel("현재 위치, \(locationName)")
STand/UI/RootView.swift:1846:                    Text(text)
STand/UI/RootView.swift:1906:                    Text(service.weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
STand/UI/RootView.swift:1910:                    Text(service.weather.map { "체감 \(Int($0.apparentTemperature.rounded()))°" } ?? "체감 --°")
STand/UI/RootView.swift:1918:                Text(service.weather?.summary ?? "날씨")
STand/UI/RootView.swift:1942:                Label("매이트", systemImage: "moon.fill")
STand/UI/RootView.swift:1945:                Label("오브제", systemImage: "sun.max.fill")
STand/UI/RootView.swift:1991:            Text("\(preferenceText) · 현재 \(Int((currentBrightness * 100).rounded())) · 기준 \(Int((threshold * 100).rounded()))")
STand/UI/RootView.swift:2015:        .accessibilityLabel("모드와 밝기 기준, \(preferenceText), 현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트")
STand/UI/RootView.swift:2016:        .accessibilityHint("레일을 좌우로 밀면 자동 기준을 조절하고, 타일을 탭하면 매이트와 오브제 모드를 강제로 전환합니다")
STand/UI/RootView.swift:2230:                    Label(batteryText, systemImage: "battery.100percent.bolt")
STand/UI/RootView.swift:2251:                        Label(
STand/UI/RootView.swift:2268:                        Button("초기화", action: onReset)
STand/UI/RootView.swift:2270:                        Text(isPortrait ? "세로 패널 편집" : "가로 패널 편집")
STand/UI/RootView.swift:2273:                        Button("저장", action: onSave)
STand/UI/RootView.swift:2338:                    Label("두 번째 라디오 추가", systemImage: "plus.circle.fill")
STand/UI/RootView.swift:2570:                    TextField("이름 (선택)", text: $displayName)
STand/UI/RootView.swift:2572:                    TextField("https://…", text: $address)
STand/UI/RootView.swift:2578:                    PasteButton(payloadType: String.self) { values in
STand/UI/RootView.swift:2583:                    .accessibilityLabel("복사한 주소 붙여넣기")
STand/UI/RootView.swift:2586:                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
STand/UI/RootView.swift:2591:                    Text("라디오 정보")
STand/UI/RootView.swift:2593:                    Text(radioInformationFooter)
STand/UI/RootView.swift:2600:                        Label("웹에서 주소 찾기", systemImage: "safari.fill")
STand/UI/RootView.swift:2603:                    Text("브라우저는 주소를 자동으로 감지하거나 입력하지 않습니다. 이용 권한이 있는 주소를 직접 복사한 뒤 돌아와 붙여넣어 주세요.")
STand/UI/RootView.swift:2608:                        Label(
STand/UI/RootView.swift:2612:                        Text("저장을 누르기 전까지 기존 채널 목록은 바뀌지 않습니다.")
STand/UI/RootView.swift:2618:                Section("재생 중 동작") {
STand/UI/RootView.swift:2619:                    Label(
STand/UI/RootView.swift:2623:                    Label(
STand/UI/RootView.swift:2631:                        Button("채널 삭제", role: .destructive) {
STand/UI/RootView.swift:2637:            .navigationTitle("라디오 채널")
STand/UI/RootView.swift:2641:                    Button("취소") {
STand/UI/RootView.swift:2647:                    Button("저장", action: save)
STand/UI/RootView.swift:2659:                Button("채널 삭제", role: .destructive) {
STand/UI/RootView.swift:2663:                Button("취소", role: .cancel) {}
STand/UI/RootView.swift:2665:                Text("삭제한 채널 주소는 되돌릴 수 없습니다.")
STand/UI/RootView.swift:2949:            .accessibilityLabel("패널 크기 조절")
STand/UI/RootView.swift:2950:            .accessibilityHint("왼쪽 위 조절점을 끌어 패널 중심을 유지한 채 크기를 변경합니다")
STand/UI/RootView.swift:3006:            .accessibilityLabel(accessibilityName)
STand/UI/RootView.swift:3007:            .accessibilityValue("크기 \(Int((transform.scale * 100).rounded()))퍼센트")
STand/UI/RootView.swift:3008:            .accessibilityHint("동작 메뉴로 패널을 이동하고 위아래로 쓸어 크기를 조절합니다")
STand/UI/RootView.swift:3027:            .accessibilityAction(named: Text("위로 이동")) {
STand/UI/RootView.swift:3030:            .accessibilityAction(named: Text("아래로 이동")) {
STand/UI/RootView.swift:3033:            .accessibilityAction(named: Text("왼쪽으로 이동")) {
STand/UI/RootView.swift:3036:            .accessibilityAction(named: Text("오른쪽으로 이동")) {
STand/UI/RootView.swift:3039:            .accessibilityAction(named: Text("패널 열기")) {
STand/UI/RootView.swift:3062:            Text(":").font(choice.font(size: 16))
STand/UI/RootView.swift:3070:        Text(value)
STand/UI/RootView.swift:3103:                Text(context.date, format: .dateTime.month().day().weekday(.wide))
STand/UI/RootView.swift:3108:                    Text(statusText)
STand/UI/RootView.swift:3169:                Text(":")
STand/UI/RootView.swift:3220:        Text(date, format: .dateTime.second(.twoDigits))
STand/UI/RootView.swift:3224:            .contentTransition(.numericText())
STand/UI/RootView.swift:3237:            .accessibilityLabel("초 (date.formatted(.dateTime.second(.twoDigits)))")
STand/UI/RootView.swift:3254:            Text(value)
STand/UI/RootView.swift:3258:                .contentTransition(.numericText())
STand/UI/RootView.swift:3315:        Label(levelText, systemImage: systemImage)
STand/UI/RootView.swift:3322:            .accessibilityLabel(accessibilityText)
STand/UI/RootView.swift:3347:    let title: String
STand/UI/RootView.swift:3355:        Button(action: action) {
STand/UI/RootView.swift:3361:                Text(title)
STand/UI/RootView.swift:3368:                    Text(status)
STand/UI/RootView.swift:3387:        .accessibilityHint(hint ?? "")
```

### 17.1 runtime·service가 UI로 전달하는 한국어 문구 원장

`AudioCaptureState.failed`, radio state message, recording error, weather mapping, validation error처럼 service/model에서 UI에 전달되는 한국어 literal의 재검색 결과다.

```text
STand/UI/StandViewModel.swift:138:        case .object: "오브제 모드"
STand/UI/StandViewModel.swift:139:        case .mate: "매이트 모드"
STand/UI/StandViewModel.swift:140:        case .startled: "화들짝 모드"
STand/Models/InternetRadioConfiguration.swift:13:            "라디오 주소를 입력해 주세요."
STand/Models/InternetRadioConfiguration.swift:15:            "라디오 주소가 너무 깁니다."
STand/Models/InternetRadioConfiguration.swift:17:            "https://로 시작하는 안전한 스트림 주소만 사용할 수 있습니다."
STand/Models/InternetRadioConfiguration.swift:19:            "서버 주소를 확인해 주세요."
STand/Models/InternetRadioConfiguration.swift:21:            "아이디나 비밀번호가 포함된 주소는 저장할 수 없습니다."
STand/Models/InternetRadioConfiguration.swift:27:    static let defaultDisplayName = "인터넷 라디오"
STand/Services/InternetRadioPlayer.swift:116:            scheduleReconnect(after: "오디오 출력을 시작할 수 없습니다.")
STand/Services/InternetRadioPlayer.swift:156:                        after: item.error?.localizedDescription ?? "스트림에 연결할 수 없습니다."
STand/Services/InternetRadioPlayer.swift:199:            self.scheduleReconnect(after: error?.localizedDescription ?? "라디오 재생이 중단되었습니다.")
STand/Services/InternetRadioPlayer.swift:210:            self.scheduleReconnect(after: "라디오 재생이 종료되었습니다.")
STand/Services/InternetRadioPlayer.swift:254:                self?.stopWithFailure("오디오 출력 기기가 분리되어 라디오를 멈췄습니다.")
STand/Services/InternetRadioPlayer.swift:264:                self.scheduleReconnect(after: "오디오 서비스가 재설정되었습니다.")
STand/Services/InternetRadioPlayer.swift:274:            self.scheduleReconnect(after: "30초 안에 스트림에 연결하지 못했습니다.")
STand/Services/InternetRadioPlayer.swift:288:            self.scheduleReconnect(after: "라디오 재생이 중단되었습니다.")
STand/Services/InternetRadioPlayer.swift:341:            stopWithFailure("오디오 중단 후 라디오를 자동으로 다시 시작하지 않았습니다.")
STand/Audio/AudioCaptureService.swift:108:            state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
STand/Audio/AudioCaptureService.swift:117:                        self.state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
STand/Audio/AudioCaptureService.swift:123:            state = .failed("마이크 상태를 확인할 수 없어 소리 감지를 사용할 수 없습니다.")
STand/Audio/AudioCaptureService.swift:151:            state = .failed("마이크 권한이 없어 소리 감지를 사용할 수 없습니다.")
STand/Audio/AudioCaptureService.swift:196:        state = .failed("시뮬레이터에서는 소리 감지를 사용하지 않습니다.")
STand/Audio/AudioCaptureService.swift:429:        "마이크 입력을 사용할 수 없습니다."
STand/Audio/AudioCaptureService.swift:594:            abortCurrentClip(message: "녹음 파일을 저장할 수 없습니다.")
STand/Audio/AudioCaptureService.swift:660:                onFailure("승인된 녹음 파일을 보관함으로 옮길 수 없습니다.")
STand/Audio/AudioCaptureService.swift:730:            abortCurrentClip(message: "녹음 파일을 시작할 수 없습니다.")
STand/Models/AppSettings.swift:21:        case .systemRounded: "시스템 둥근체"
STand/Models/AppSettings.swift:22:        case .pretendard: "프리텐다드"
STand/Models/AppSettings.swift:23:        case .kakaoBigSans: "카카오 Big Sans"
STand/Models/AppSettings.swift:24:        case .nanumGothic: "나눔고딕"
STand/Models/AppSettings.swift:25:        case .tenada: "태나다"
STand/Models/AppSettings.swift:26:        case .blackHanSans: "검은고딕"
STand/Models/AppSettings.swift:27:        case .doHyeon: "도현"
STand/Models/AppSettings.swift:28:        case .paperlogyBold: "페이퍼로지 Bold"
STand/Models/AppSettings.swift:29:        case .nexonLv1Gothic: "넥슨 Lv.1 고딕"
STand/Models/AppSettings.swift:111:        case .color: "오렌지"
STand/Models/AppSettings.swift:112:        case .grayscale: "그레이"
STand/Models/AppSettings.swift:113:        case .midnight: "미드나이트"
STand/Models/AppSettings.swift:114:        case .sage: "세이지"
STand/Models/AppSettings.swift:137:        case .automatic: "자동"
STand/Models/AppSettings.swift:138:        case .object: "오브제 유지"
STand/Models/AppSettings.swift:139:        case .mate: "매이트 유지"
STand/Services/RecordingLibrary.swift:23:        if name.contains("-today-merged") { return "오늘 녹음 합본" }
STand/Services/RecordingLibrary.swift:27:        return "합친 녹음"
STand/Services/RecordingLibrary.swift:179:            "합치려면 녹음이 두 개 이상 필요합니다."
STand/Services/RecordingLibrary.swift:181:            "오디오가 없는 녹음이 포함되어 있습니다."
STand/Services/RecordingLibrary.swift:183:            "합친 녹음 파일을 만들 수 없습니다."
STand/Services/RecordingLibrary.swift:185:            "합본은 만들었지만 원본 일부를 삭제하지 못했습니다. \(message)"
STand/Services/RecordingLibrary.swift:187:            "녹음을 합치지 못했습니다. \(message)"
STand/Services/RecordingLibrary.swift:743:                exporter.error?.localizedDescription ?? "알 수 없는 오류"
STand/Services/WeatherService.swift:13:        case 0: "맑음"
STand/Services/WeatherService.swift:14:        case 1: "대체로 맑음"
STand/Services/WeatherService.swift:15:        case 2: "구름 조금"
STand/Services/WeatherService.swift:16:        case 3: "흐림"
STand/Services/WeatherService.swift:17:        case 45, 48: "안개"
STand/Services/WeatherService.swift:18:        case 51, 53, 55, 56, 57: "이슬비"
STand/Services/WeatherService.swift:19:        case 61, 63, 65, 66, 67: "비"
STand/Services/WeatherService.swift:20:        case 71, 73, 75, 77: "눈"
STand/Services/WeatherService.swift:21:        case 80, 81, 82: "소나기"
STand/Services/WeatherService.swift:22:        case 85, 86: "눈 소나기"
STand/Services/WeatherService.swift:23:        case 95, 96, 99: "뇌우"
STand/Services/WeatherService.swift:24:        default: "날씨 정보"
```
## 18. 작성 후 재전수 감사 결과

- Swift/plist/entitlements/privacy 대상 24개 파일을 다시 열거했다. 앱 Swift 14개, 앱 plist/entitlements/privacy 3개, Share 4개, Widget 2개, XCTest 1개이며 0절 목록과 일치했다.
- UI interaction 재검색은 gesture/button/toggle/slider/paste/share/accessibility action expression 120개, navigation/sheet/dialog/link expression 23개를 반환했다. 2절 화면별 표와 17절 425행 UI source-expression 원장으로 다시 대조했다.
- runtime/service 한국어 literal 63개를 별도 재검색해 17.1절에 보존했다. UI 생성자 밖 validation/reconnect/permission/writer/weather/merge 문구를 포함한다.
- 최신 XCTest 선언은 130개, `XCTAssert*` 호출은 541개다. 16절 coverage map과 checklist의 자동-test 영역을 다시 대조했다. XCUITest/snapshot/ViewInspector 사용은 검색 결과 0개였다.
- 0.24.1 재감사 때 theme 표시명/RGB, `SettingsStore` key, restore marker, AppSettings 경로와 당시 충돌을 기록했다. 최신 재감사에서는 R1 즉시 삭제와 잘못된 hint가 `a97743a`에서 해소됐음을 반영했고, torch-off 10%, 0% endpoint lock 부재, hidden controls 등 나머지 실제 코드 특성은 유지했다.
- Markdown table 열 수, fenced block 짝, trailing whitespace, patch whitespace를 검사했다. 두 문서 밖 파일 변경은 없다.
- 위 검색 범위에서 새로 남은 unmatched 화면·input constructor는 없었다. 다만 0절·16절에 열거한 실기기/UI 항목은 실행하지 않았으므로 확인 완료로 판정하지 않는다.

## 19. Android 구현 완료의 증거 규칙


1. 각 checklist 행은 `[구현]`, `[자동]`, `[UI]`, `[실기기]`를 별도로 체크한다. 하나의 unit test로 네 칸을 대체하지 않는다.
2. Android code reference와 test name, 기기/API/orientation/accessibility setting, screenshot/log를 결과 옆에 기록한다.
3. iOS에서 dead인 UI는 Android에 추가하지 않고, migration-only라 표시한다.
4. 플랫폼상 불가능한 것은 checklist의 차이 표에 이유/API 근거/사용자 의미 보존 대안을 기록한다.
5. 이 문서의 source line과 현재 iOS HEAD가 달라지면 문서를 먼저 재생성하고 parity를 다시 판정한다.
