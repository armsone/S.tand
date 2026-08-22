# S.tand Mac 자체 업데이트 릴리스 절차

S.tand의 Mac Catalyst 빌드는 앱에 내장된 순수 macOS 플러그인 `STandUpdaterBridge.bundle`을 통해
Sparkle 2.9.2로 자체 업데이트한다. 흐름: 확인 → 서명 검증된 DMG 다운로드 → 호스트 앱 종료 →
원자적 교체 설치 → 재실행. iPhone/iPad 빌드에는 Sparkle 관련 코드·설정이 전혀 포함되지 않는다.

- 피드: `https://nasfinder.com/appcasts/stand.xml`
- 배포물: 노터라이즈된 `S.tand-macOS-<MARKETING_VERSION>.dmg` (사용자용 ZIP 배포 금지)
- 버전 비교 기준: `CURRENT_PROJECT_VERSION`(현재 337417). 사용자에게는 버전 `2.0.0`과
  표시 빌드 `202608230737`을 보여준다. 공개 배포된 0.30.0에는 업데이터가 없었고 0.33.0이
  자동 업데이트의 시작 기준선이므로 0.30.0 사용자는 한 번 수동 설치가 필요하다.

## 1. EdDSA 키 준비 (최초 1회)

Sparkle 배포 아카이브(https://github.com/sparkle-project/Sparkle/releases, 2.9.2)의 `bin/generate_keys`를 실행한다.

```sh
./bin/generate_keys
```

- 비밀 키는 로그인 키체인에 저장된다. **저장소나 CI 로그에 절대 넣지 않는다.**
- 공개 키는 `Configuration/Versions.xcconfig`에 포함한다. 공개 키는 비밀이 아니며,
  비밀 키만 로그인 Keychain의 `STand` 계정에 남긴다.

## 2. 아카이브와 공증 DMG 생성

Developer ID 인증서와 `ccmb-notary` notarytool 프로필이 준비된 Mac에서 아래 한 명령을 실행한다.

```sh
scripts/package-macos.sh
```

스크립트가 Mac Catalyst 아카이브, Developer ID 내보내기, Sparkle 브리지·공개키 확인,
설치용 DMG 생성, Apple 공증과 앱·DMG 스테이플을 순서대로 수행한다. 결과는
`artifacts/macos/S.tand-macOS-<MARKETING_VERSION>.dmg`이다.

## 3. appcast 생성·서명

노터라이즈된 DMG만 들어 있는 디렉터리에서:

```sh
scripts/make-mac-appcast.sh <dmg가 있는 디렉터리>
```

내부적으로 Sparkle의 `generate_appcast`를 호출한다. 키체인의 비밀 키로 각 항목에
`sparkle:edSignature`를 서명하고 `<디렉터리>/stand.xml`(appcast)을 생성한다.
`--download-url-prefix`로 DMG의 실제 다운로드 URL prefix를 지정한다(스크립트 인자 참고).

## 4. 배포

- DMG를 다운로드 URL prefix 위치에 업로드한다.
- `stand.xml`을 `https://nasfinder.com/appcasts/stand.xml`로 업로드한다.
- 반드시 HTTPS로만 서빙한다.

## 구성 요약 (이미 저장소에 반영됨)

- `InfoMac.plist`: `SUFeedURL`, `SUPublicEDKey=$(STAND_SPARKLE_ED_PUBLIC_KEY)`,
  `SUEnableAutomaticChecks`, `SUAllowsAutomaticUpdates`, `SUAutomaticallyUpdate`,
  `SUScheduledCheckInterval=86400`, `SUEnableInstallerLauncherService`(샌드박스 설치 XPC).
- `STandMac.entitlements`: 샌드박스용 mach-lookup 예외
  `com.armsone.stand-spks`, `com.armsone.stand-spki`.
- `STandUpdaterBridge` 타깃: macOS 전용 번들, Sparkle 2.9.2(SwiftPM, exact)를 링크·내장.
  Catalyst 빌드에서만 `PlugIns`로 임베드된다(platformFilter=maccatalyst).
