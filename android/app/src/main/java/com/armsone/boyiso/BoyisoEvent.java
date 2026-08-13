package com.armsone.boyiso;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

final class BoyisoEvent {
    static final String HEARTBEAT = "heartbeat";
    static final String SOUND = "sound";
    static final String MOVEMENT = "movement";
    static final String DETAIL_BIG_SOUND = "big_sound";
    static final String DETAIL_CONTINUOUS_SOUND = "continuous_sound";

    final String id;
    final String sourceId;
    final String sourceName;
    final String kind;
    final long sentAtMilliseconds;
    final Double intensity;
    final String detail;
    final boolean monitoring;
    final Integer batteryPercent;

    BoyisoEvent(String id, String sourceId, String sourceName, String kind,
                long sentAtMilliseconds, Double intensity, String detail,
                boolean monitoring, Integer batteryPercent) {
        this.id = id;
        this.sourceId = sourceId;
        this.sourceName = sourceName;
        this.kind = kind;
        this.sentAtMilliseconds = sentAtMilliseconds;
        this.intensity = intensity;
        this.detail = detail;
        this.monitoring = monitoring;
        this.batteryPercent = batteryPercent;
    }

    static BoyisoEvent heartbeat(String sourceId, String sourceName, boolean monitoring,
                                 Integer batteryPercent) {
        return create(sourceId, sourceName, HEARTBEAT, null, null, monitoring, batteryPercent);
    }

    static BoyisoEvent sound(String sourceId, String sourceName, String detail,
                             double intensity, Integer batteryPercent) {
        return create(sourceId, sourceName, SOUND, intensity, detail, true, batteryPercent);
    }

    private static BoyisoEvent create(String sourceId, String sourceName, String kind,
                                      Double intensity, String detail, boolean monitoring,
                                      Integer batteryPercent) {
        return new BoyisoEvent(UUID.randomUUID().toString(), sourceId, sourceName, kind,
                System.currentTimeMillis(), intensity, detail, monitoring, batteryPercent);
    }

    byte[] encodeBytes() {
        JSONObject json = new JSONObject();
        try {
            json.put("version", 1);
            json.put("id", id);
            json.put("sourceID", sourceId);
            json.put("sourceName", sourceName);
            json.put("kind", kind);
            json.put("sentAtMilliseconds", sentAtMilliseconds);
            if (intensity != null) json.put("intensity", intensity);
            if (detail != null) json.put("detail", detail);
            json.put("monitoring", monitoring);
            if (batteryPercent != null) json.put("batteryPercent", batteryPercent);
            return json.toString().getBytes(StandardCharsets.UTF_8);
        } catch (JSONException error) {
            throw new IllegalStateException("Unable to encode event", error);
        }
    }

    static BoyisoEvent decode(byte[] value) throws JSONException {
        JSONObject json = new JSONObject(new String(value, StandardCharsets.UTF_8));
        if (json.getInt("version") != 1) throw new JSONException("Unsupported Boyiso version");
        return new BoyisoEvent(
                json.getString("id"),
                json.getString("sourceID"),
                json.getString("sourceName"),
                json.getString("kind"),
                json.getLong("sentAtMilliseconds"),
                json.has("intensity") ? json.getDouble("intensity") : null,
                json.has("detail") ? json.getString("detail") : null,
                json.getBoolean("monitoring"),
                json.has("batteryPercent") ? json.getInt("batteryPercent") : null
        );
    }
}
