package com.armsone.boyiso;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

final class BleFrames {
    private static final byte VERSION = 1;
    private static final int HEADER_SIZE = 9;
    private static final AtomicInteger NEXT_MESSAGE_ID = new AtomicInteger(1);

    static List<byte[]> fragment(byte[] payload, int maximumFrameBytes) {
        if (maximumFrameBytes <= HEADER_SIZE) throw new IllegalArgumentException("BLE frame too small");
        int chunkSize = maximumFrameBytes - HEADER_SIZE;
        int count = Math.max(1, (payload.length + chunkSize - 1) / chunkSize);
        if (count > 0xffff) throw new IllegalArgumentException("BLE payload too large");
        int messageId = NEXT_MESSAGE_ID.getAndIncrement();
        List<byte[]> frames = new ArrayList<>(count);
        for (int index = 0; index < count; index++) {
            int start = index * chunkSize;
            int length = Math.min(chunkSize, payload.length - start);
            ByteBuffer frame = ByteBuffer.allocate(HEADER_SIZE + length).order(ByteOrder.BIG_ENDIAN);
            frame.put(VERSION);
            frame.putInt(messageId);
            frame.putShort((short) index);
            frame.putShort((short) count);
            frame.put(payload, start, length);
            frames.add(frame.array());
        }
        return frames;
    }

    static final class Reassembler {
        private static final long RETENTION_MILLIS = 30_000;
        private final Map<Integer, Pending> pending = new HashMap<>();

        synchronized byte[] accept(byte[] frame, long nowMillis) {
            prune(nowMillis);
            if (frame == null || frame.length < HEADER_SIZE) return null;
            ByteBuffer buffer = ByteBuffer.wrap(frame).order(ByteOrder.BIG_ENDIAN);
            if (buffer.get() != VERSION) return null;
            int messageId = buffer.getInt();
            int index = Short.toUnsignedInt(buffer.getShort());
            int count = Short.toUnsignedInt(buffer.getShort());
            if (count == 0 || index >= count || count > 512) return null;
            byte[] chunk = new byte[buffer.remaining()];
            buffer.get(chunk);
            Pending value = pending.get(messageId);
            if (value == null || value.chunks.length != count) {
                value = new Pending(count, nowMillis);
                pending.put(messageId, value);
            }
            if (value.chunks[index] == null) {
                value.chunks[index] = chunk;
                value.received++;
            }
            if (value.received != count) return null;
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            for (byte[] part : value.chunks) output.write(part, 0, part.length);
            pending.remove(messageId);
            return output.toByteArray();
        }

        private void prune(long nowMillis) {
            pending.entrySet().removeIf(entry -> nowMillis - entry.getValue().createdAt > RETENTION_MILLIS);
        }

        private static final class Pending {
            final byte[][] chunks;
            final long createdAt;
            int received;

            Pending(int count, long createdAt) {
                chunks = new byte[count][];
                this.createdAt = createdAt;
            }
        }
    }
}
