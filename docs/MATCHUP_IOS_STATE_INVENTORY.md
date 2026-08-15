# S.tand iOS matchup 상태 인벤토리

기준: iOS `main` / `2335ec382883c769bf70113ce6a724014af4eaa9`, `1.0.0 (0.29.5)`

공통 profile은 `fixture=ui_catalog_v2`, `locale=ko-KR`, `timezone=Asia/Seoul`, dark appearance, animation off, font scale 1.0이다. 기본 phone은 iPhone 17 Pro이며 adaptive 분기는 iPad portrait/landscape와 큰 글자에서 별도 확인한다. 아래 `captured`만 현재 fresh PNG가 있으며 나머지는 source/runtime inventory이므로 paired visual verification 전까지 `확인 필요`다.

| Route/state ID | Class | Distinct state | Current evidence |
|---|---|---|---|
| `first_launch_permissions` | Visual/Functional | OS 권한 요청 전 3카드 설명 | captured |
| `first_launch_request_camera` | Functional/Forced OS | 카메라 요청과 거부/허용 후 다음 단계 | trace 필요 |
| `first_launch_request_microphone` | Functional/Forced OS | 마이크 요청과 거부/허용 후 다음 단계 | trace 필요 |
| `first_launch_request_location` | Functional/Forced OS | 위치 요청과 거부/허용 후 홈 진입 | trace 필요 |
| `home_portrait` | Visual/Functional | 자동·오브제 기본, 고정 라디오 2개, 날씨 placeholder | captured |
| `home_landscape` | Visual/Functional | landscapeRight adaptive layout | captured |
| `home_object_locked` | Visual/Functional | 오브제 유지/100% 잠금 표시 | 확인 필요 |
| `home_mate` | Visual/Functional | 매이트 모드와 잠금 overlay | 확인 필요 |
| `home_startle` | Visual/Functional | 화들짝 조명과 복귀 | trace/실기기 필요 |
| `home_inactive` | Visual/Functional | 세션 비활성 `S.tand 시작` | 확인 필요 |
| `home_brightness_hud` | Visual/Functional | 상하 drag 앱 밝기 HUD | 확인 필요 |
| `home_radio_volume_hud` | Visual/Functional | 좌우 drag 라디오 볼륨 HUD | 확인 필요 |
| `home_clock_scale_hud` | Visual/Functional | pinch 시계 크기 HUD | 확인 필요 |
| `home_face_down` | Visual/Functional | 완전 암전과 face-up 복귀 | 실기기 필요 |
| `home_radio_idle_loading_playing_reconnecting_error` | Content/state/Functional | 각 라디오 재생 상태와 전환 | 확인 필요 |
| `home_weather_loading_denied_error_loaded` | Content/state/Functional | 위치·날씨 상태 | 확인 필요 |
| `home_editor` | Visual/Functional | portrait 패널 편집 | captured |
| `home_editor_landscape` | Visual/Functional | landscape 패널 편집 | 확인 필요 |
| `home_editor_font_palette` | Visual/Functional | 글꼴 palette 열린 편집 | 확인 필요 |
| `home_editor_radio_grouped` | Visual/Functional | 라디오 40% 결합/분리 | 확인 필요 |
| `recordings_report_populated` | Visual/Content | 고정 3개 샘플 수면 리포트 | captured |
| `recordings_report_empty` | Visual/Content | 잠자리 없음 | 확인 필요 |
| `recordings_management` | Visual/Content | 원본 3개와 보관 현황 | captured |
| `recordings_management_empty` | Visual/Content | 원본/합본 없음 | 확인 필요 |
| `recordings_selection_dock` | Visual/Functional | 1개/2개 이상 선택과 합치기 enable | 확인 필요 |
| `recordings_playback_dock` | Visual/Functional | 재생·일시정지·2×·닫기 | 확인 필요 |
| `recordings_delete_clip_confirmation` | Visual/Functional | 단일 녹음 삭제 | 확인 필요 |
| `recordings_delete_selected_confirmation` | Visual/Functional | 선택 삭제 | 확인 필요 |
| `recordings_delete_all_confirmation` | Visual/Functional | 전체 삭제 | 확인 필요 |
| `recordings_merge_delete_confirmation` | Visual/Functional | 합친 뒤 원본 삭제 | 확인 필요 |
| `recordings_operation_error` | Visual/Functional | 합치기/삭제 실패 alert | 확인 필요 |
| `boyiso_setup` | Visual/Functional | 역할 미선택 초기 화면 | captured |
| `boyiso_host_scanning` | Visual/Functional | 호스트 탐색/공간 | 확인 필요 |
| `boyiso_guest_scanning` | Visual/Functional | 게스트 탐색/연결 | 확인 필요 |
| `boyiso_connected` | Visual/Functional | 연결 peer/상태 | 확인 필요 |
| `boyiso_disconnected_banner` | Visual/Content | 연결 끊김 banner | 확인 필요 |
| `boyiso_greeting_overlay` | Visual/Functional | 톡톡/소리 overlay | 확인 필요 |
| `settings_top` | Visual/Functional | hero, 화면/시계, 권한 카드 | captured |
| `settings_midnight_theme` | Visual/Functional | 미드나이트 선택 상태 | captured |
| `settings_grayscale_theme` | Visual/Functional | 그레이스케일 선택 상태 | 확인 필요 |
| `settings_sage_theme` | Visual/Functional | 세이지 선택 상태 | 확인 필요 |
| `settings_large_text` | Visual/Accessibility | 큰 글자 adaptive grid | 확인 필요 |
| `settings_tablet` | Visual/Responsive | 720pt 이상 2열 + radio full width | 확인 필요 |
| `clock_font_options` | Visual/Functional | 9개 번들 + 시스템 둥근체 | captured |
| `font_licenses` | Visual/Content | 저작권 목록 | captured |
| `font_license_detail` | Visual/Content/Functional | 전문 선택·복사/불러오기 실패 | 확인 필요 |
| `settings_lower_sections` | Visual/Functional | 정보/복원/라디오 영역 | captured |
| `radio_channel_editor` | Visual/Functional | 기존 채널 inline 편집 | captured |
| `radio_channel_add` | Visual/Functional | 빈 채널 추가 | 확인 필요 |
| `radio_channel_validation_error` | Visual/Functional | 이름/HTTPS/길이 오류 | 확인 필요 |
| `radio_delete_confirmation` | Visual/Functional | 채널 삭제 confirmation | captured |
| `restore_confirmation` | Visual/Functional | 추천 설정 복원 confirmation | captured |
| `radio_browser` | Visual/Functional | 주소 toolbar/닫기/뒤로/새로고침 | 확인 필요 |
| `radio_browser_favorites` | Visual/Functional | 즐겨찾기 목록 | 확인 필요 |
| `radio_browser_error` | Visual/Functional | 로드 실패/재시도 | 확인 필요 |
| `share_radio_import_confirmation` | Visual/Functional | 공유 URL 확인·저장·취소 | 확인 필요 |
| `widget_lock_screen_circular` | Visual/Functional | 원형 잠금화면 심벌 | 확인 필요 |
| `widget_home_sizes` | Visual/Functional | 지원 홈 위젯 크기와 앱 열기 | 확인 필요 |

## 기능 trace JSONL

각 상호작용은 다음 필드를 한 줄 JSON으로 기록한다.

`routeStateId`, `fixtureId`, `profile`, `entrySteps`, `preState`, `input`, `expectedPostState`, `actualPostState`, `sideEffects`, `persistedAfterRelaunch`, `validationOrError`, `accessibility`, `capture`, `verifier`, `status`.

`profile`에는 platform/device class/device/OS/pixel size/density/orientation/theme/locale/timezone/font scale/revision/dirty를 포함한다. `capture`에는 original/normalized 경로, 두 SHA-256, app bounds와 최소 OS mask를 포함한다.
