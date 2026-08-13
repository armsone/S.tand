package com.armsone.boyiso;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertNull;

public class BleFramesTest {
    @Test public void fragmentedPayloadReassemblesInOrder() {
        byte[] payload = new byte[600];
        for (int index = 0; index < payload.length; index++) payload[index] = (byte) (index % 251);
        List<byte[]> frames = BleFrames.fragment(payload, 64);
        BleFrames.Reassembler reassembler = new BleFrames.Reassembler();
        byte[] result = null;
        for (int index = 0; index < frames.size(); index++) {
            result = reassembler.accept(frames.get(index), 1_000 + index);
            if (index < frames.size() - 1) assertNull(result);
        }
        assertArrayEquals(payload, result);
    }

    @Test public void fragmentsCanArriveOutOfOrder() {
        byte[] payload = new byte[180];
        List<byte[]> frames = BleFrames.fragment(payload, 48);
        BleFrames.Reassembler reassembler = new BleFrames.Reassembler();
        byte[] result = null;
        for (int index = frames.size() - 1; index >= 0; index--) {
            result = reassembler.accept(frames.get(index), 2_000 + index);
        }
        assertArrayEquals(payload, result);
    }
}
