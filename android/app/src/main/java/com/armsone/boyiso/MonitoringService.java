package com.armsone.boyiso;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.net.wifi.WifiManager;
import android.os.BatteryManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.provider.Settings;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public final class MonitoringService extends Service implements LanTransport.Listener, BleTransport.Listener {
    static volatile boolean isActive;
    static final String ACTION_START = "com.armsone.boyiso.START";
    static final String ACTION_STOP = "com.armsone.boyiso.STOP";
    static final String ACTION_STATE = "com.armsone.boyiso.STATE";
    static final String ACTION_EVENT = "com.armsone.boyiso.EVENT";
    static final String EXTRA_ROLE = "role";
    static final String EXTRA_ROOM_CODE = "roomCode";
    static final String ROLE_HOST = "host";
    static final String ROLE_GUEST = "guest";
    private static final String CHANNEL_ID = "boyiso_monitoring";
    private static final int NOTIFICATION_ID = 4101;
    private static final long STALE_MILLIS = 15_000;

    private final EventDeduplicator deduplicator = new EventDeduplicator();
    private final Map<String, Long> sourceLastSeen = new ConcurrentHashMap<>();
    private ScheduledExecutorService scheduler;
    private LanTransport lan;
    private BleTransport ble;
    private AudioRecord audioRecord;
    private Thread audioThread;
    private PowerManager.WakeLock wakeLock;
    private WifiManager.MulticastLock multicastLock;
    private String role;
    private String sourceId;
    private String sourceName;
    private volatile boolean running;
    private volatile int lanCount;
    private volatile int bleCount;
    private volatile String latestError;

    @Override public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        sourceId = getSharedPreferences("boyiso", MODE_PRIVATE).getString("source_id", null);
        if (sourceId == null) {
            sourceId = UUID.randomUUID().toString();
            getSharedPreferences("boyiso", MODE_PRIVATE).edit().putString("source_id", sourceId).apply();
        }
        sourceName = Build.MANUFACTURER + " " + Build.MODEL;
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        if (ACTION_STOP.equals(intent.getAction())) {
            stopMonitoring();
            stopSelf();
            return START_NOT_STICKY;
        }
        if (!ACTION_START.equals(intent.getAction()) || running) return START_NOT_STICKY;
        role = intent.getStringExtra(EXTRA_ROLE);
        String roomCode = intent.getStringExtra(EXTRA_ROOM_CODE);
        if ((!ROLE_HOST.equals(role) && !ROLE_GUEST.equals(role)) || roomCode == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            startMonitoring(new CryptoCodec(roomCode));
        } catch (IllegalArgumentException error) {
            latestError = "방 코드는 영문·숫자 8자리여야 합니다";
            broadcastState();
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private void startMonitoring(CryptoCodec codec) {
        running = true;
        isActive = true;
        int foregroundType = 0;
        if (Build.VERSION.SDK_INT >= 29) {
            foregroundType = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE;
            if (ROLE_GUEST.equals(role)
                    && checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                foregroundType |= android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;
            }
            startForeground(NOTIFICATION_ID, buildNotification(), foregroundType);
        } else {
            startForeground(NOTIFICATION_ID, buildNotification());
        }
        acquireLocks();
        lan = new LanTransport(this, codec, sourceId, this);
        ble = new BleTransport(this, codec, this);
        scheduler = Executors.newSingleThreadScheduledExecutor();
        if (ROLE_GUEST.equals(role)) {
            lan.startGuest();
            if (hasBluetoothPermissions()) ble.startGuest();
            else latestError = "블루투스 권한 없이 Wi-Fi만 사용 중입니다";
            startAudioCapture();
            scheduler.scheduleAtFixedRate(this::sendHeartbeat, 0, 5, TimeUnit.SECONDS);
        } else {
            lan.startHost();
            if (hasBluetoothPermissions()) ble.startHost();
            else latestError = "블루투스 권한 없이 Wi-Fi만 사용 중입니다";
            scheduler.scheduleAtFixedRate(this::expireStaleSources, 1, 2, TimeUnit.SECONDS);
        }
        broadcastState();
    }

    private void acquireLocks() {
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (ROLE_GUEST.equals(role)) {
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Boyiso:GuestMonitoring");
            wakeLock.acquire();
        }
        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        multicastLock = wifiManager.createMulticastLock("BoyisoNsd");
        multicastLock.setReferenceCounted(false);
        multicastLock.acquire();
    }

    private boolean hasBluetoothPermissions() {
        if (Build.VERSION.SDK_INT < 31) return true;
        return checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
                && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
                && (ROLE_HOST.equals(role)
                || checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED);
    }

    private void sendHeartbeat() {
        if (!running) return;
        BoyisoEvent heartbeat = BoyisoEvent.heartbeat(sourceId, sourceName,
                audioRecord != null && audioRecord.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING,
                batteryPercent());
        lan.sendFromGuest(heartbeat);
        ble.sendFromGuest(heartbeat);
    }

    private Integer batteryPercent() {
        BatteryManager manager = (BatteryManager) getSystemService(Context.BATTERY_SERVICE);
        int value = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
        return value >= 0 && value <= 100 ? value : null;
    }

    private void startAudioCapture() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            latestError = "마이크 권한이 없어 소리 감시를 시작하지 못했습니다";
            broadcastState();
            return;
        }
        int sampleRate = 16_000;
        int minimum = AudioRecord.getMinBufferSize(sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) {
            latestError = "이 기기에서 마이크 입력을 준비하지 못했습니다";
            return;
        }
        int bufferSize = Math.max(minimum, 4_096);
        audioRecord = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize);
        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release();
            audioRecord = null;
            latestError = "마이크를 시작하지 못했습니다";
            return;
        }
        audioRecord.startRecording();
        audioThread = new Thread(() -> captureAudio(bufferSize), "BoyisoAudio");
        audioThread.start();
    }

    private void captureAudio(int bufferSizeBytes) {
        short[] samples = new short[Math.max(1_024, bufferSizeBytes / 2)];
        SoundEventDetector detector = new SoundEventDetector();
        while (running && audioRecord != null) {
            int count = audioRecord.read(samples, 0, samples.length, AudioRecord.READ_BLOCKING);
            if (count > 0) {
                detector.observe(samples, count, System.currentTimeMillis(), (detail, level) -> {
                    BoyisoEvent event = BoyisoEvent.sound(sourceId, sourceName, detail,
                            level / 100.0, batteryPercent());
                    lan.sendFromGuest(event);
                    ble.sendFromGuest(event);
                    broadcastLocalDetection(event);
                });
            } else if (count < 0) {
                latestError = "마이크 입력이 중단되었습니다 (" + count + ")";
                broadcastState();
                break;
            }
        }
    }

    @Override public void onEvent(BoyisoEvent event, String path) {
        if (!ROLE_HOST.equals(role)) return;
        long now = System.currentTimeMillis();
        sourceLastSeen.put(event.sourceId, now);
        if (!deduplicator.accept(event.id, now)) return;
        if (!BoyisoEvent.HEARTBEAT.equals(event.kind)) broadcastReceivedEvent(event, path);
        broadcastState();
    }

    @Override public void onPathCount(String path, int count) {
        if ("LAN".equals(path)) lanCount = count; else if ("BLE".equals(path)) bleCount = count;
        latestError = null;
        broadcastState();
    }

    @Override public void onTransportError(String path, String message) {
        latestError = path + ": " + (message == null ? "연결 오류" : message);
        broadcastState();
    }

    private void expireStaleSources() {
        long now = System.currentTimeMillis();
        if (sourceLastSeen.entrySet().removeIf(entry -> now - entry.getValue() > STALE_MILLIS)) {
            broadcastState();
        }
    }

    private void broadcastReceivedEvent(BoyisoEvent event, String path) {
        Intent update = new Intent(ACTION_EVENT).setPackage(getPackageName());
        update.putExtra("sourceName", event.sourceName);
        update.putExtra("kind", event.kind);
        update.putExtra("detail", event.detail);
        update.putExtra("intensity", event.intensity == null ? 0.0 : event.intensity);
        update.putExtra("path", path);
        update.putExtra("timestamp", event.sentAtMilliseconds);
        sendBroadcast(update);
        updateNotification("소리 이벤트를 확인했습니다");
    }

    private void broadcastLocalDetection(BoyisoEvent event) {
        Intent update = new Intent(ACTION_EVENT).setPackage(getPackageName());
        update.putExtra("sourceName", sourceName);
        update.putExtra("kind", event.kind);
        update.putExtra("detail", event.detail);
        update.putExtra("intensity", event.intensity == null ? 0.0 : event.intensity);
        update.putExtra("path", "이 기기");
        update.putExtra("timestamp", event.sentAtMilliseconds);
        sendBroadcast(update);
    }

    private void broadcastState() {
        Intent update = new Intent(ACTION_STATE).setPackage(getPackageName());
        update.putExtra("running", running);
        update.putExtra("role", role);
        update.putExtra("lanCount", lanCount);
        update.putExtra("bleCount", bleCount);
        update.putExtra("guestCount", sourceLastSeen.size());
        update.putExtra("monitoring", audioRecord != null
                && audioRecord.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING);
        update.putExtra("error", latestError);
        sendBroadcast(update);
        updateNotification(null);
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                getString(com.armsone.boyiso.R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription(getString(com.armsone.boyiso.R.string.notification_channel_description));
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private Notification buildNotification() {
        return buildNotification(null);
    }

    private Notification buildNotification(String override) {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        String text = override;
        if (text == null) {
            if (ROLE_GUEST.equals(role)) text = "아이 곁에서 소리를 살피는 중";
            else text = sourceLastSeen.isEmpty() ? "아이 곁 기기 연결을 기다리는 중"
                    : sourceLastSeen.size() + "대의 아이 곁 기기를 살피는 중";
        }
        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
                .setContentTitle("보이소")
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pendingIntent)
                .build();
    }

    private void updateNotification(String text) {
        if (!running) return;
        getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, buildNotification(text));
    }

    private void stopMonitoring() {
        running = false;
        isActive = false;
        if (scheduler != null) scheduler.shutdownNow();
        if (audioRecord != null) {
            try { audioRecord.stop(); } catch (IllegalStateException ignored) { }
            audioRecord.release();
            audioRecord = null;
        }
        if (audioThread != null) {
            audioThread.interrupt();
            audioThread = null;
        }
        if (lan != null) { lan.stop(); lan = null; }
        if (ble != null) { ble.stop(); ble = null; }
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        if (multicastLock != null && multicastLock.isHeld()) multicastLock.release();
        sourceLastSeen.clear();
        lanCount = 0;
        bleCount = 0;
        broadcastState();
        stopForeground(STOP_FOREGROUND_REMOVE);
    }

    @Override public void onDestroy() {
        stopMonitoring();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
