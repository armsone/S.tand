package com.armsone.boyiso;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class WalkiePressPolicyTest {
    @Test public void firstPressIsAlwaysAccepted() {
        assertTrue(new WalkiePressPolicy().tryAccept(0));
    }

    @Test public void rapidRepeatedPressIsThrottledUntilCooldownPasses() {
        WalkiePressPolicy policy = new WalkiePressPolicy();
        assertTrue(policy.tryAccept(1_000));
        assertFalse(policy.tryAccept(1_001));
        assertFalse(policy.tryAccept(1_000 + WalkiePressPolicy.COOLDOWN_MILLIS - 1));
        assertTrue(policy.tryAccept(1_000 + WalkiePressPolicy.COOLDOWN_MILLIS));
    }

    @Test public void cooldownMatchesIOSPolicy() {
        assertTrue(WalkiePressPolicy.COOLDOWN_MILLIS == 3_000);
    }
}
