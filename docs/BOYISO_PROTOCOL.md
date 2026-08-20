# 보이소 근거리 프로토콜 v2

보이소는 한 공간에 여러 `볼 사람`, 여러 `말할 사람`, 여러 `무전기`가 참여한다. 사용자
화면에서는 이 명칭만 사용하고 wire 역할 값은 각각 `host`, `guest`, `walkie`를 쓴다.
`무전기`는 주변 소리·움직임 사건을 만들지 않으며, 사용자가 버튼을 누른
경우에만 사건을 보낸다. 원음과 녹음 파일은 전송하지 않는다.

## 초대와 암호화

초대는 `stand://boyiso?v=2&room=<12-byte base64url>&key=<32-byte base64url>` 형식이다.
공간을 새로 만들 때마다 두 값을 새로 생성하며 QR을 가진 사람만 참여할 수 있다.

- event key: `SHA-256("boyiso-v2|" + roomKey)`
- AES-256-GCM payload: `12-byte nonce || ciphertext || 16-byte tag`
- LAN frame: Base64 payload 뒤 LF
- BLE: UUID `B0150001-7A4D-4F6B-9D7A-5354414E4401`, characteristic
  `B0150002-7A4D-4F6B-9D7A-5354414E4401`, 9-byte big-endian 분할 헤더

사건 JSON version은 2이며 `id`, `sourceID`, `sourceName`, `role`, `kind`,
`sentAtMilliseconds`, `monitoring`, `sessionActive`와 선택적인 `intensity`, `detail`,
`batteryPercent`, `displayMode`를 포함한다.

## 근거리 메시

모든 역할이 `_boyiso._tcp` listener/browser와 BLE peripheral/central을 가능한 범위에서
동시에 유지한다. 처음 받은 사건을 다시 두 경로로 전달하고 사건 ID를 10분간 기억해 경로
중복과 메시 고리를 차단한다. heartbeat는 5초, 참여자 stale 기준은 15초다. 끊어진 LAN과
BLE 연결은 자동 재시도한다.

`toktok/greeting`은 모든 역할이 5초 cooldown으로 보낼 수 있다. 소리 사건은
`big_sound`, `continuous_sound`, `finger_snap`, 움직임은 `movement/turning`을 사용한다.
`walkie/press`는 `무전기` 역할만 3초 cooldown으로 보내는 의도적 호출 사건이며,
수신 화면은 감지된 소리와 같은 수준의 높은 시인성 반응(전체 화면 오버레이·차임)을 보인다.
`walkie` 역할과 `walkie` 사건 종류를 모르는 구버전 클라이언트는 해당 사건 디코딩에
실패해 조용히 무시하며, 다른 사건 처리에는 영향이 없다. protocol version은 2를 유지한다.

## 소리 감지·녹음·화들짝 동시 기준

- 매이트 감시 시작 후 첫 60초는 학습만 하고 녹음, 화들짝, 보이소 소리 사건을 만들지 않는다.
- 학습 뒤 RMS 문턱은 `max(사용자 감도, 주변 바닥 소음 + 여유폭)`이다. 여유폭은 조용한 방부터
  10dB·12dB·14dB이며 최종 문턱 범위는 `-58...-18 dB`다. 자동 기준은 사용자 설정보다
  민감해질 수 없다.
- 일반 소리는 문턱을 60ms 이상 통과해야 하며, 연속 소리는 같은 보수적 문턱을 2초 이상
  유지해야 한다. 박수·핑거스냅은 별도 피크 기준을 쓰고 기본 `-18 dB` 미만 피크에는 반응하지 않는다.
- 코골이·잠꼬대만 녹음을 승인한다. 뒤척임은 화들짝 후보지만 저장하지 않으며, 애매한 생활
  소음과 외부 TV·라디오는 저장하거나 화들짝을 만들지 않는다. 앱 자체 라디오 재생 중에는 감지를 쉰다.
- 공통 회귀 벡터의 측정값 `RMS -53.19 dB`, 최대 20ms RMS `-46.69 dB`, 피크 `-36.92 dB`는
  권장 사용자 감도 `-36 dB`에서 녹음·화들짝·보이소 사건이 모두 0이어야 한다.

보이소는 위 기준을 통과한 사건 종류와 강도만 전송하며 원음과 녹음 파일은 전송하지 않는다.

## 플랫폼 경계

iOS는 앱이 전면에 있고 화면이 켜진 동안에만 화들짝 시각 반응을 보인다. 화면을 강제로
깨우지 않으며 무음·집중 모드·알림 차단을 우회하지 않는다. Bluetooth·백그라운드 오디오가
허용되는 동안 근거리 처리를 계속 시도하지만 앱 종료나 iOS 스케줄링 제한에서는 연결과
알림을 보장하지 않는다. 계정·클라우드·원거리 중계와 APNs provider는 이번 범위가 아니다.
