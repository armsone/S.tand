# S.tand UI 카탈로그

iOS 화면을 Android 구현 자료로 전달하기 위한 자동 스크린샷 모음이다. 로그인이나 실제 네트워크 연결 없이 고정된 샘플 설정과 라디오 채널을 사용한다.

## 생성

```bash
./scripts/capture-ui-catalog.sh
```

결과는 `artifacts/ui-catalog/index.html`과 `artifacts/ui-catalog/` 아래에 생성된다. `originals/`는 XCUITest가 만든 무손실 원본, `screenshots/`는 비교 좌표계에 맞게 방향만 정규화한 PNG이며, `manifest.json`에는 두 파일의 SHA-256·픽셀 크기·방향·`fixtureId`/`sharedProfile`·고정 시각·revision/dirty 상태와 dirty 소스 fingerprint가 기록된다. 캡처는 `iPhone 17 Pro` 시뮬레이터 하나에서 직렬로 실행한다.

## 포함 범위

- 최초 권한 설명
- 홈 세로·가로 화면(가로 원본은 보존하고 비교본만 방향 정규화)
- 홈 패널 편집
- 수면 소리 목록
- 보이소 초기 설정
- 설정 상단·하단
- 테마와 시계 글꼴 옵션
- 인터넷 라디오 채널 편집·삭제 확인
- 추천 설정 복원 확인
- 내장 폰트 저작권

새 화면이나 시각적으로 구분되는 상태를 추가하면 `STandUITests/STandUICatalogTests.swift`에 진입 동작과 `capture` 호출을 함께 추가한다. 모든 토글의 가능한 조합을 만들기보다 Android 구현이 달라지는 고유 상태를 한 장씩 기록한다.
