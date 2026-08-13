package com.armsone.boyiso;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

final class EventDeduplicator {
    private static final long RETENTION_MILLIS = 10 * 60 * 1000L;
    private static final int MAX_ENTRIES = 2_000;
    private final LinkedHashMap<String, Long> seen = new LinkedHashMap<>();

    synchronized boolean accept(String eventId, long nowMillis) {
        prune(nowMillis);
        if (seen.containsKey(eventId)) {
            return false;
        }
        seen.put(eventId, nowMillis);
        if (seen.size() > MAX_ENTRIES) {
            Iterator<String> iterator = seen.keySet().iterator();
            if (iterator.hasNext()) {
                iterator.next();
                iterator.remove();
            }
        }
        return true;
    }

    private void prune(long nowMillis) {
        Iterator<Map.Entry<String, Long>> iterator = seen.entrySet().iterator();
        while (iterator.hasNext()) {
            if (nowMillis - iterator.next().getValue() > RETENTION_MILLIS) {
                iterator.remove();
            } else {
                break;
            }
        }
    }
}
