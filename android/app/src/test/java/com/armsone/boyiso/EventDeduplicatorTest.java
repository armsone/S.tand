package com.armsone.boyiso;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class EventDeduplicatorTest {
    @Test public void sameEventFromLanAndBleIsAcceptedOnce() {
        EventDeduplicator deduplicator = new EventDeduplicator();
        assertTrue(deduplicator.accept("event-1", 1_000));
        assertFalse(deduplicator.accept("event-1", 1_001));
        assertTrue(deduplicator.accept("event-2", 1_002));
    }

    @Test public void expiredEventCanBeAcceptedAgain() {
        EventDeduplicator deduplicator = new EventDeduplicator();
        assertTrue(deduplicator.accept("event-1", 1_000));
        assertTrue(deduplicator.accept("event-1", 10 * 60 * 1_000L + 1_001));
    }
}
