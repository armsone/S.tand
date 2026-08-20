package com.armsone.boyiso;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;

public class BoyisoEventTest {
    @Test public void walkiePressEventRoundTripsOnTheWire() throws Exception {
        BoyisoEvent press = BoyisoEvent.walkiePress("source-1", "무전기", 80);

        BoyisoEvent decoded = BoyisoEvent.decode(press.encodeBytes());

        assertEquals("walkie", decoded.kind);
        assertEquals(BoyisoEvent.DETAIL_WALKIE_PRESS, decoded.detail);
        assertEquals("source-1", decoded.sourceId);
        assertEquals("무전기", decoded.sourceName);
        assertEquals(Double.valueOf(1.0), decoded.intensity);
        assertEquals(Integer.valueOf(80), decoded.batteryPercent);
        assertFalse(decoded.monitoring);
    }

    @Test public void decodeStillAcceptsEventsWithoutOptionalFields() throws Exception {
        BoyisoEvent heartbeat = BoyisoEvent.heartbeat("source-2", "게스트", true, null);

        BoyisoEvent decoded = BoyisoEvent.decode(heartbeat.encodeBytes());

        assertEquals(BoyisoEvent.HEARTBEAT, decoded.kind);
        assertNull(decoded.intensity);
        assertNull(decoded.detail);
        assertNull(decoded.batteryPercent);
    }
}
