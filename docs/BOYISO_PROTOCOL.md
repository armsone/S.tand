# 보이소 기기 연동 규약 v1

보이소는 아이 곁의 `게스트` 기기가 감지한 특별한 소리와 움직임을 부모·보호자의 `호스트` 기기에 직접 전달한다. 의료 진단이나 울음 판별을 제공하지 않으며 원음·녹음 파일을 전송하지 않는다.

## 연결 구조

- 하나의 8자리 돌봄 공간 코드에 호스트와 게스트 여러 대가 참여할 수 있다.
- 동일 LAN에서는 게스트가 `_boyiso._tcp` Bonjour/NSD 서비스를 열고 호스트가 찾아 TCP로 연결한다.
- BLE에서는 게스트가 peripheral/GATT server, 호스트가 central/GATT client가 된다.
- Wi-Fi와 BLE는 동시에 독립적으로 유지한다. 어느 한 경로만 살아 있어도 사건을 전달하며, 같은 사건 ID는 수신 측에서 한 번만 표시한다.
- 게스트는 5초마다 heartbeat를 보내고 호스트는 15초 동안 받지 못한 기기를 연결 끊김으로 표시한다.

## 암호화

- 방 코드는 대문자 영문·숫자 8자리다.
- 키: `SHA-256(UTF-8("boyiso-v1|" + normalizedRoomCode))`
- 본문: UTF-8 JSON
- 암호화: AES-256-GCM, 12-byte nonce, 16-byte authentication tag
- 전송 데이터: `nonce || ciphertext || tag`
- LAN frame: 위 데이터를 Base64로 인코딩하고 LF 하나로 끝낸다.

방 코드는 공유 비밀이다. 추측과 주변 기기의 오접속을 줄이기 위한 최소 장치이며, 인터넷 계정이나 서버를 사용하지 않는다.

## 사건 JSON

필드는 `version`, `id`, `sourceID`, `sourceName`, `kind`, `sentAtMilliseconds`, `intensity`, `detail`, `monitoring`, `batteryPercent`다. `kind`는 `heartbeat`, `sound`, `movement` 중 하나이며 선택 값은 JSON에서 생략할 수 있다.

## BLE frame

암호화 데이터가 한 번의 notify 크기를 넘으면 다음 9-byte big-endian header로 나눈다.

1. version: UInt8, 현재 `1`
2. message ID: UInt32
3. chunk index: UInt16
4. chunk count: UInt16
5. encrypted payload chunk

모든 조각을 받은 뒤 암호 인증에 성공한 사건만 사용한다.

## 안전 원칙

- 호스트는 heartbeat 단절을 조용한 상태로 해석하지 않는다.
- 원음과 녹음 파일은 기기 밖으로 보내지 않는다.
- 보이소는 보호자의 직접 확인이나 인증된 의료·안전 감시장치를 대신하지 않는다.
- iOS 게스트의 소리 감시는 현재 앱이 전면 실행 중일 때만 유지된다. Android 게스트는 사용자가 시작한 foreground service와 지속 알림으로 감시 상태를 알린다.
