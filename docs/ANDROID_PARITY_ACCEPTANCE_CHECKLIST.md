# S.tand Android 동등성 인수검사 체크리스트

Android 기존 확정 기준: iOS `0f664b2`, `1.0.0 (0.24.1)`

최신 대조 기준: iOS `33711c009b7568779504a73685d616d6ec115db0`, `1.0.0 (0.25.1)` (`Configuration/Versions.xcconfig` 우선)

상세 명세: `docs/ANDROID_IMPLEMENTATION_HANDOFF.md`
작성 원칙: 아래 각 행의 네 증거를 독립적으로 체크한다. 미실행은 `[ ]`로 둔다.

표기:

- `[구현]`: Android 소스와 접근 가능한 UI가 존재하고 code reference 기록
- `[자동]`: JVM/unit/instrumented policy test name과 결과 기록
- `[UI]`: Compose/UI Automator/Espresso로 화면·입력·navigation 검증
- `[실기기]`: 실제 Android device에서 센서/권한/오디오/화면을 직접 검증

## 0. 기준·빌드·증거

- [ ] [구현] Android parity 문서에 기존 확정 기준 `0f664b2 / 0.24.1`과 최신 목표 `33711c0 / 0.25.1`을 함께 기록
- [ ] [구현] 커밋 원장에 `bf8c46b`, `a68f474`, `769406c`, `a97743a`, `33711c0` 5개가 모두 있고 각 적용/폐기 판정 기록
- [ ] [구현] 최종 소스와 project에서 YouTube 모델·패널·설정·player가 제거됐고 라디오 최대 2채널만 남았음을 전역 검색으로 증명
- [ ] [자동] 0.24.3 payload의 unknown `youtube`/layout `youtube` key가 crash 없이 무시되고 다시 노출되지 않는 migration fixture
- [ ] [구현] 실제 `Versions.xcconfig=0.25.1`; 작업 트리 `PROJECT_RULES.md=0.24.4` 문구 불일치를 Android 기준으로 사용하지 않음
- [ ] [자동] debug/release compile, unit, instrumented, lint 결과와 날짜 기록
- [ ] [UI] 테스트 계정/fixture 없이 cold start부터 전체 navigation crawl 성공
- [ ] [실기기] 최소 phone portrait/landscape, tablet/≥600dp, 최소/최신 지원 API 각각 기록
- [ ] [실기기] font scale 1.0/1.3/2.0, TalkBack, dark mode, reduced animation 상태 기록
- [ ] iOS handoff의 “직접 미확인” 항목을 Android 완료로 자동 승격하지 않음

### 0.1 최신 델타 필수 게이트

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] OS dialog 전 최초 권한 설명 화면
- [ ] [구현] 최종 3카드 원문·아이콘: 카메라와 플래시/camera, 마이크/mic, 위치 정보/location
- [ ] [UI] 설명 화면 중 홈 시작·전역 gesture·편집·시트 진입 차단
- [ ] [UI] 미결정 권한만 카메라→마이크→위치 순서; 각 deny 뒤 다음 요청과 앱 시작 계속
- [ ] [자동] 첫 누락 즉시, 이후 random 3...7 process launch 간격; lower/upper clamp와 countdown fixture
- [ ] [UI] 회전·Activity/scene 재생성·foreground 복귀가 launch counter를 중복 감소시키지 않음
- [ ] [자동] 모든 권한 granted면 reminder key 삭제와 이후 미표시
- [ ] [UI] 자동 앱 시작/날씨 refresh가 microphone/location dialog를 직접 띄우지 않음; 설정 명시 enable은 복구 흐름 유지
- [ ] [UI] 좁은 폭 browser toolbar 2행 fallback과 항상 보이는 별도 X close
- [ ] [UI] 설정 Hero pill 읽기 전용, segmented `자동/오브제 유지/매이트 유지` 직접 선택·저장
- [ ] [UI] 편집 panel이 safe area/editor toolbar/bottom controls/font palette 내부에 clamp
- [ ] [UI] recordings selection/playback dock의 한 줄/두 줄 fallback과 48dp targets
- [ ] [UI] radio swipe/context 삭제가 confirm 전에는 데이터 불변
- [ ] [자동] [ ] [실기기] Mate 진입 후 0·59.999초 화들짝 억제, 정확히 60초 허용
- [ ] [자동] Mate 중복 set은 deadline 불변, Object 왕복은 새 60초, monotonic clock 사용
- [ ] [실기기] 첫 60초에도 microphone 학습·후보 감지·녹음 pipeline은 정상이고 lamp/event/조건부 torch만 억제

증거 템플릿:

| 항목 | Android 파일:줄 | 자동 테스트 | UI 테스트 | 기기/API·직접 결과 | 상태/차이 |
|---|---|---|---|---|---|
| 예: 홈 가로 볼륨 |  |  |  |  |  |

## 1. 전체 화면·진입·종료

각 행: `[구현] [ ]  [자동] [ ]  [UI] [ ]  [실기기] [ ]`

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 홈 H0: cold/warm/deep-link 진입, active session 자동 시작
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 시작 H1: inactive/low-battery 상태와 `S.tand 시작`
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 밝기 HUD H2, 볼륨 HUD H3, 시계 크기 HUD H4
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] face-down 암전 H5 및 face-up 복구
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] portrait/landscape 화면 편집 E0, font palette E1
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 홈 라디오 editor R0, channel manager R1, add/edit R2
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 내장 브라우저 B0, favorites B1, error B2
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 설정 S0, inline radio S1, font S2, licenses S3/S4
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 수면 소리 P0, selection dock P1, playback dock P2
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] channel/restore/recording delete dialogs A0~A3
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] Android Sharesheet X0 대응, one URL/explicit confirm/cancel
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] lockscreen/home shortcut/widget W0 대응과 cold/warm open
- [ ] 모든 화면의 system back, swipe dismiss, process recreation 후 초안/저장 규칙 기록

## 2. 홈 화면·표시·제스처

### 2.1 표시와 레이아웃

- [ ] [구현] 상단 좌 mode/중앙 S.tand/우 battery, footer `0.25.1 · 밝기 N%`
- [ ] [자동] mode/battery/footer formatting 전 상태
- [ ] [UI] controls/banners/panels z-order와 face-down black overlay
- [ ] [실기기] status/navigation bars immersive, portrait/landscape rotation, burn-in offset 매분
- [ ] [구현] start screen icon/title/explanation/button 정확 문구
- [ ] [UI] battery/recording error banner move+opacity와 터치 차단
- [ ] [구현] bottom은 현재 recordings/settings 두 tile만; legacy torch/brightness/stop tile 미노출
- [ ] [자동] portrait<700/large width column/wrapping policy
- [ ] [자동] current iOS처럼 `controlsVisible=false` 쓰기 경로가 없음을 parity/dead-path로 기록; 80pt reveal/silhouette를 임의 노출하지 않음

### 2.2 일반 홈 제스처

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 전체 화면 drag 최소 slop 후 최초 우세축 1회 고정
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 위 drag brightness 증가/아래 감소, 화면 높이 50%가 0↔100%, clamp
- [ ] brightness는 앱 lamp만 변경하고 Android system brightness를 쓰지 않음
- [ ] drag 시작/끝과 100% 1초 object lock, 95% release stability 검증
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 오른쪽 drag radio volume 증가/왼쪽 감소, 화면 폭 50%가 0↔100%, clamp
- [ ] radio volume은 player만 변경, media stream/system/recording gain 불변
- [ ] player stop/new channel/reconnect 후 같은 process volume 유지; process restart 100% reset
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 일반 홈 전체 단일 탭: stand→35%, Mate→80%, 2초, automatic, light haptic
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 일반 홈 전체 더블탭: 오렌지→그레이→미드나이트→세이지, .28초, light haptic
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 전체 0.8초 long press/max12pt: current orientation editor, medium haptic
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] pinch clock scale .70...1.35, HUD, 종료1.2초 후 fade
- [ ] tap/double/long/vertical/horizontal/pinch/radio child gesture 경쟁 테스트
- [ ] 편집 또는 modal 열린 동안 root drag/tap/long press가 상태를 바꾸지 않음

### 2.3 홈 라디오·하단

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 각 radio panel tap play/stop/switch
- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 각 radio panel 0.8초 long press 해당 channel editor + medium haptic
- [ ] grouped left/right half가 정확히 해당 channel에 작동
- [ ] recording tile이 radio stop/audio monitoring suspension 후 list open
- [ ] Settings tile open/close 후 monitoring state 보존

## 3. 화면 편집

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] portrait/landscape 독립 초안과 저장
- [ ] 모든 clock/seconds/date/battery/weather/radio panel 최소 48dp hit target
- [ ] drag/pinch/resize/appear/inset 변경 후 panel이 safe area·상단 editor chrome·하단 controls/font palette 내부로 clamp
- [ ] center guide middle-10% snap, 축 최초 진입 selection haptic
- [ ] pinch와 top-left handle 모두 30...200%; handle은 중심 유지
- [ ] handle 시각 크기/target/dash border/crosshair/editor backdrop 동일
- [ ] radio two panels overlap≥40% merge: average center/min scale/medium haptic
- [ ] grouped radio tap/double tap split: x±.11/light haptic
- [ ] weather group overlap≥40% merge, double tap split x .16 spacing
- [ ] one home radio + second saved channel일 때 `두 번째 라디오 추가` manager 진입
- [ ] clock tap font palette toggle; portrait390×190/landscape650×126 max; 3 columns
- [ ] `초기화`는 current orientation defaults 초안만, bottom order 유지
- [ ] `저장`만 persistence; back/process recreation의 draft disposal 정책 명시
- [ ] TalkBack adjustable scale±10%, move±5%, open custom actions

## 4. 테마·시계·날씨·디자인

- [ ] [구현] 4 home radial gradient exact RGB/opacity/radius와 grayscale 처리
- [ ] [자동] color token screenshot values/gradient stops
- [ ] [UI] theme transition .28, background intensity .08
- [ ] [실기기] OLED black, banding, portrait/landscape visual comparison
- [ ] FlipPanelSurface gradient/stroke/shadow/split gap를 panel별 비교
- [ ] 10 clock fonts(9 bundled+system), PostScript 대응, vertical optical offsets
- [ ] 12-hour flip face, independent seconds, date width200/240, numeric transitions
- [ ] exact portrait/landscape default panel transforms fixture test
- [ ] weather cells 94/123.333, split4/3, metadata18/inset7/8, typography
- [ ] WMO Korean condition/icon mapping 전 case test
- [ ] long location marquee icon fixed/text only, 18pt/s, pause1.2s, return
- [ ] location denied/loading/failed placeholder states

## 5. 설정 화면

### 5.1 구조·큰 화면

- [ ] [구현] Hero→screen/permission/detection/info grid→radio full-width 순서
- [ ] width<720 1열, ≥720 2열; Hero와 마지막 radio card는 full width, 중간 4 cards만 grid; padding 14/24, spacing14
- [ ] Settings background/card gradients, radius22, dividers, header icons
- [ ] `완료` dismiss, orientation/process recreation state
- [ ] font scale 1.0/1.3/2.0에서 문구/controls 무손실

### 5.2 controls

- [ ] 4 theme tiles select/persist/accessibility selected
- [ ] Hero pill은 읽기 전용 상태 표시; 아래 segmented picker로 automatic/object/mate 유지 직접 선택, stopped일 때 disabled
- [ ] flash/camera/mic/location switches 각각 app setting과 OS permission 분리
- [ ] camera denied/mic denied/location denied toggle은 OS Settings open
- [ ] 모든 camera/mic/location status copy 전 분기 문자열 test
- [ ] audio meter 12×58/min4/.12초와 status 전 분기
- [ ] wake-again and recording switches default true/persist/runtime sync
- [ ] recordings open pauses monitor and dismiss resumes only eligible Mate
- [ ] info version 1.0.0(0.25.1), Open-Meteo external link, privacy/safety 3문장
- [ ] recommended restore confirmation exact copy; radio/layout/theme/settings reset, OS permission 유지

### 5.3 font/license

- [ ] 3-column 10 font previews and selection haptic/persistence
- [ ] 9 bundled copyright rows and exact long explanation
- [ ] each full license readable/selectable; missing file fallback

## 6. 인터넷 라디오

### 6.1 validation/storage/management

- [ ] HTTPS exact, host required, credential reject, empty/long address errors
- [ ] name trim/prefix30/empty=`인터넷 라디오`, URL max2048
- [ ] stable UUID, maximum2, ordered first two home panels, migration fixtures
- [ ] settings card empty/add/edit/close/paste/browser/save/delete states
- [ ] save success/error haptic and inline localized message
- [ ] active row state copy: 대기/연결/재생/자동 재연결/실패
- [ ] R0 shared/import editor interactive dismiss disabled and cancel clears pending
- [ ] R1 add/edit push, pencil/context/swipe actions, reorder and haptic
- [ ] R1 swipe/context 삭제 모두 title/message/destructive/cancel confirmation 후 삭제
- [ ] R1 hint는 selected `현재 홈에 표시되는 채널입니다`, other `편집에서 순서를 바꾸면 홈에 표시할 수 있습니다`
- [ ] active remove/URL update stops; name-only update continues

### 6.2 playback/audio focus

- [ ] loading timeout30s; reconnect 2/4/8/15/30 최대5
- [ ] ended/failed/paused/media-reset 재연결, user stop cancels stale tasks
- [ ] output route removal failed stop
- [ ] audio focus interruption ends/resumes only system permitted; denied resume releases monitoring suspension
- [ ] app inactive/background stops playback; foreground does not auto-play
- [ ] radio active stops mic recording but motion remains; stop resumes eligible Mate
- [ ] volume process state applied to every new/reconnected player

## 7. 내장 브라우저

### 7.1 toolbar/input

- [ ] [구현] [ ] [자동] [ ] [UI] [ ] [실기기] 44/48dp back-close, address44...56, primary, reload, favorite order
- [ ] 넓은 폭은 back/address/primary/reload/favorite/X 한 줄; 좁은 폭은 back/address/primary + reload/favorite/X 두 줄, spacing7
- [ ] address min width 88; 별도 X는 history/popup 상태와 무관하게 browser dismiss
- [ ] tap back: popup→close, history→back, none→dismiss
- [ ] 0.5s back long press: popup close else dismiss regardless history
- [ ] address Go: HTTPS/domain/search conversion, trim/max length/errors
- [ ] primary tap load/stop; 0.5s long press explicit clipboard paste+load; empty error
- [ ] reload disabled before loaded; progress separator1/progress2 and animations
- [ ] favorites toggle/X/4 exact entries/order/URLs/help copy
- [ ] error panel exact all messages and dismiss

### 7.2 WebView security/lifecycle

- [ ] ephemeral cookies/cache/storage; close/process recreation policy documented
- [ ] HTTPS+host+no credentials every request/response; no cleartext exception
- [ ] download/attachment/unsupported MIME/custom/file/blob reject
- [ ] file chooser/upload/drag/drop/file paste reject
- [ ] page camera/mic/motion/geolocation permission deny
- [ ] TLS default validation only, other auth cancel
- [ ] target blank popup same WebView, popup close returns previous URL
- [ ] WebView edge history gestures and Android system back consistent
- [ ] browser/app inactive pauses page audio/video; active resumes; close stops
- [ ] renderer/process termination error + reload recovery
- [ ] AirPlay/PiP/fullscreen analog disabled where applicable
- [ ] network/DOM/media never sniffed for stream; browser never auto-fills editor
- [ ] screen rotation/≥600dp preserves URL/history/loading/popup without media leak

## 8. microphone·분류·녹음

- [ ] capture runs only foreground+active session+Mate+mic enabled+no radio/playback suspension
- [ ] permission unknown/granted/denied, simulator/emulator/no-input failure copy
- [ ] interruption/route/media reset cleanup and resume-only-permitted
- [ ] adaptive calibration60s and threshold -58...-18, percentile/adaptation fixtures
- [ ] clap .06 attack/rise/peak/refractory1.5 and relative-rise fixtures
- [ ] snore≥.58/sleepTalk≥.60 keep; movement≥.55 wakes/not saved
- [ ] exact pre/post roll, max segment, pending cap4, AAC M4A settings from Swift constants
- [ ] approved-only atomic publish; hidden pending; startup stale cleanup
- [ ] continuous loud rollover bounded; rejected event removes all pending
- [ ] writer start/write/move errors exact UI and no orphan public file
- [ ] [실기기] real mic quiet/noisy room calibration and candidate recording
- [ ] [실기기] overnight memory/storage/battery/thermal and background cleanup

## 9. 움직임·face-down·화들짝·torch

- [ ] acceleration .16/rotation1.4 and minor-noise fixture
- [ ] Mate 실제 진입 timestamp를 monotonic clock으로 저장; nil 또는 elapsed<60이면 wake callback no-op, elapsed≥60 허용
- [ ] 같은 Mate 재적용은 timestamp reset 금지; Object 전환은 clear; process 재생성 후 안전하게 새 60초 적용
- [ ] 60초 gate는 화들짝 event/lamp/torch에만 적용하며 microphone 학습·감지·recording session은 계속
- [ ] stale sensor generation callback ignored after stop
- [ ] face-down enter .82/exit .62 hysteresis
- [ ] face-down app-only black, system brightness unchanged, face-up restore
- [ ] Mate + enabled only clap/relative/movement triggers startle
- [ ] maximum=max(.7,base), hold5 default, fade30 default, 50ms progression
- [ ] startle event persists even without recording and closes lifecycle-correctly
- [ ] torch only movement-triggered Mate+recent≤60s dark≤.16
- [ ] torch enabled 100%, **disabled 10% 실제 코드 정책** 검증/제품 결함 결정 기록
- [ ] no camera reading/bright/stale/Object/touch-only → torch off
- [ ] torch unavailable/busy silent fallback and 150/450ms retry
- [ ] low-battery/background/face-down/permission change cleanup

## 10. camera·자동 모드·battery

- [ ] automatic boundary app brightness≤.40 Mate, >.40 Object; forced modes ignore signal
- [ ] Object→Mate20s, Mate→Object35s, fresh-camera dark transition4s and recheck cancellation
- [ ] camera dark≤.16/bright≥.28/middle retain; reading age60; interval45; min observation1s
- [ ] camera only active automatic Mate; Object/adjustment/startle skip/cancel
- [ ] median sample/exposure compensation fixture or documented equivalent
- [ ] no image/video persisted/transmitted; camera indicator not hidden
- [ ] denied/unavailable/busy/timeout fallback and status copy
- [ ] unplugged≤20% stops; charging does not auto-restart; explicit button required
- [ ] idle/screen-awake flag only active session; every exit clears

## 11. 날씨·위치

- [ ] coarse-only runtime permission/rationale; denied→OS settings
- [ ] disabled clears weather/location/lastUpdated/progress immediately
- [ ] refresh caching/generation prevents stale overwrite
- [ ] Open-Meteo exact HTTPS query/current fields/timezone/1day
- [ ] Korean reverse-geocode component dedupe
- [ ] failure leaves clock/date/other panels functional; placeholder exact
- [ ] all WMO summary/icon cases and precipitation/apparent text
- [ ] marquee behavior and TalkBack one combined label

## 12. 수면 소리·세션·파일

- [ ] empty/summary/today/session/selection/merged/status layout and exact copy
- [ ] session is real Mate interval; ≤30min resume, >30min split
- [ ] legacy groups ≤90min previous-end gap and ±15min inferred padding/`시간 추정`
- [ ] abnormal recovery/open session/exact ±5s clip association
- [ ] timeline clip thick marker/startle thin marker, clamp and time labels
- [ ] session and merged cards expand/collapse .24s
- [ ] original selection checkbox, play/body, ellipsis share/delete
- [ ] today merge≥2, selected merge≥2 chronological, original preserve default
- [ ] merge-and-delete confirmation and honest partial failure
- [ ] single/selected/all delete updates actual files+manifest and reloads
- [ ] all delete catches unindexed m4a/pending but preserves current open session
- [ ] playback play/pause/seek/close; 2× gain default true (speed 아님)
- [ ] audio focus and monitoring suspension/resume
- [ ] font scale accessibility vertical/adaptive layout and docks
- [ ] actual share intent grants temporary URI permission and source remains private

## 13. 저장·복구·migration·privacy

- [ ] all current AppSettings defaults table matches handoff
- [ ] portrait/landscape exact transforms and grouping/order persistence
- [ ] atomic DataStore/JSON write; corrupt/future raw payload not overwritten until user mutation
- [ ] legacy single radio/stable selection/unknown controls/missing fields fixtures
- [ ] one-time migrations do not repeatedly override later user choice
- [ ] restore recommended resets app state including radio but not OS permission
- [ ] shared latest-one draft private, malformed clear, explicit save/cancel
- [ ] recordings/manifest/pending in private no-backup storage
- [ ] no accounts/analytics/ads/tracking/upload; Data Safety matches implementation
- [ ] browser ephemeral/private security settings and release debugging off
- [ ] external URLs/share payloads/file names/settings payload validated as untrusted

## 14. lifecycle·interruptions·failure injection

- [ ] cold start, warm start, active→inactive→background→active exact state matrix
- [ ] background stops radio/mic/motion/camera/torch/page media and releases awake flag
- [ ] active session boolean/session grouping resumes without false overnight segment
- [ ] radio and recording playback suspensions independently insert/remove
- [ ] audio focus denied resume, route unplug, media reset failure injection
- [ ] network offline/timeout/DNS/TLS/unsupported MIME/WebView renderer death
- [ ] storage full/read-only/file missing/partial delete/export failure
- [ ] permission revoke while active for mic/camera/location/motion
- [ ] low battery threshold crossing/charging/restart
- [ ] process kill during settings write/shared draft/recording pending/merge

## 15. 접근성

- [ ] TalkBack order: home mode/brand/battery/panels/buttons/footer, no duplicate hidden HUD/silhouette
- [ ] home adjustable brightness ±10 and custom mode/theme/editor/clock actions
- [ ] panel name/scale adjustable/move four directions/open action
- [ ] radio state/selected/edit/delete labels and misleading R1 hint disposition
- [ ] browser back-vs-close, default/custom close, paste-load, reload, favorite labels
- [ ] recording session expanded state/count, clip select/play/menu, docks
- [ ] all icon-only targets ≥48dp; color not sole state cue
- [ ] font scale 2.0 no lost critical text/buttons in every screen/dialog/orientation
- [ ] TalkBack + switch access + bold/high contrast/reduced animations tested
- [ ] dynamic content updates announce errors/status without excessive repeats

## 16. 문구 전수 대조

- [ ] Android string resources vs Swift `Text/Button/Label/navigationTitle/accessibility/errorDescription` 자동 추출 diff 첨부
- [ ] 홈/start/banner/HUD/editor exact Korean copy
- [ ] Settings cards/toggles/help/status/privacy/safety/restore exact copy
- [ ] radio validation/status/help/delete/shared import exact copy
- [ ] browser toolbar/favorites/help/every error exact copy
- [ ] recordings empty/summary/actions/dialogs/timeline/playback exact copy
- [ ] share receiver/widget/shortcut exact copy or platform-equivalent difference recorded
- [ ] `N`, URL, date/time/duration/plural formatting edge cases test

## 17. 의도적 플랫폼 차이 기록

완료 전 각 차이에 API/OS 근거와 의미 보존 대안을 적는다. “구현이 어려움”은 사유가 아니다.

| iOS 항목 | Android 차이 | 불가능/차이 근거 | 사용자 의미 보존 구현 | 자동/UI/실기기 증거 | 승인 |
|---|---|---|---|---|---|
| accessoryCircular lockscreen widget |  |  |  |  |  |
| SF Symbols |  |  |  |  |  |
| ultraThinMaterial |  |  |  |  |  |
| PasteButton privacy UI |  |  |  |  |  |
| AVAudioSession semantics |  |  |  |  |  |
| WKWebView ephemeral/popup |  |  |  |  |  |
| haptic strength |  |  |  |  |  |

## 18. 최종 누락 감사

- [ ] Android navigation destinations ↔ handoff ID H0~W0 양방향 diff 0건
- [ ] Android clickable/gesture semantics ↔ handoff 화면별 입력 표 양방향 diff 0건
- [ ] Android visible/accessibility strings ↔ Swift string extraction 양방향 diff 0건 또는 승인 차이
- [ ] Android constants/defaults/layout tokens ↔ Swift sources/tests diff 0건
- [ ] Android error branches/lifecycle callbacks ↔ Swift state/error tables diff 0건
- [ ] iOS XCTest 130개 policy coverage를 Android test matrix에 각각 매핑
- [ ] UI automation 없는 항목을 실기기 증거로 채우거나 미완료 유지
- [ ] phone/tablet portrait/landscape/large text/TalkBack evidence 첨부
- [ ] 실제 mic/camera/torch/motion/location/radio/WebView/recording device evidence 첨부
- [ ] 플랫폼 차이 전부 승인; 미승인/미검증 항목 0개일 때만 전체 완료
