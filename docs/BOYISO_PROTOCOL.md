# 보이소 근거리 프로토콜 v2

보이소는 한 공간에 여러 `볼 사람`과 여러 `말할 사람`이 참여한다. 사용자 화면에서는 이
명칭만 사용하고 wire 역할 값은 Android 호환을 위해 각각 `host`, `guest`를 쓴다. 원음과
녹음 파일은 전송하지 않는다.

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

## 플랫폼 경계

iOS는 앱이 전면에 있고 화면이 켜진 동안에만 화들짝 시각 반응을 보인다. 화면을 강제로
깨우지 않으며 무음·집중 모드·알림 차단을 우회하지 않는다. Bluetooth·백그라운드 오디오가
허용되는 동안 근거리 처리를 계속 시도하지만 앱 종료나 iOS 스케줄링 제한에서는 연결과
알림을 보장하지 않는다. 계정·클라우드·원거리 중계와 APNs provider는 이번 범위가 아니다.
