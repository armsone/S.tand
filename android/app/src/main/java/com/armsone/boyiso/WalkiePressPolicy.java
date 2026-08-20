package com.armsone.boyiso;

/**
 * 무전기 호출 버튼의 연타·오조작을 막는 최소 간격 정책. iOS의
 * BoyisoWalkiePressPolicy(3초)와 같은 값을 유지해야 한다.
 */
final class WalkiePressPolicy {
    static final long COOLDOWN_MILLIS = 3_000;

    private boolean hasSent;
    private long lastSentAtMillis;

    boolean tryAccept(long nowMillis) {
        if (hasSent && nowMillis - lastSentAtMillis < COOLDOWN_MILLIS) return false;
        hasSent = true;
        lastSentAtMillis = nowMillis;
        return true;
    }
}
