package com.armsone.boyiso;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.os.Build;
import android.os.ParcelUuid;

import java.security.GeneralSecurityException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@SuppressLint("MissingPermission")
final class BleTransport {
    static final UUID SERVICE_UUID = UUID.fromString("B0150001-7A4D-4F6B-9D7A-5354414E4401");
    static final UUID NOTIFY_UUID = UUID.fromString("B0150002-7A4D-4F6B-9D7A-5354414E4401");
    private static final UUID CCC_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final int REQUESTED_MTU = 185;
    private static final int MAX_FRAME_BYTES = REQUESTED_MTU - 3;

    interface Listener {
        void onEvent(BoyisoEvent event, String path);
        void onPathCount(String path, int count);
        void onTransportError(String path, String message);
    }

    private final Context context;
    private final CryptoCodec codec;
    private final Listener listener;
    private final BluetoothManager manager;
    private final Set<BluetoothDevice> subscribedHosts = Collections.synchronizedSet(new HashSet<>());
    private final Map<String, Integer> negotiatedMtu = Collections.synchronizedMap(new HashMap<>());
    private final Map<String, BluetoothGatt> guestGatts = Collections.synchronizedMap(new HashMap<>());
    private final Map<String, BleFrames.Reassembler> reassemblers = Collections.synchronizedMap(new HashMap<>());
    private final Set<String> readyGuests = Collections.synchronizedSet(new HashSet<>());
    private final ArrayDeque<NotificationTask> notificationQueue = new ArrayDeque<>();
    private BluetoothGattServer gattServer;
    private BluetoothGattCharacteristic notifyCharacteristic;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothLeScanner scanner;
    private boolean notificationInFlight;
    private volatile boolean running;

    BleTransport(Context context, CryptoCodec codec, Listener listener) {
        this.context = context.getApplicationContext();
        this.codec = codec;
        this.listener = listener;
        manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
    }

    boolean isAvailable() {
        BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
        return adapter != null && adapter.isEnabled();
    }

    void startGuest() {
        if (!isAvailable()) {
            listener.onTransportError("BLE", "블루투스를 사용할 수 없습니다");
            return;
        }
        running = true;
        gattServer = manager.openGattServer(context, serverCallback);
        if (gattServer == null) {
            listener.onTransportError("BLE", "BLE 서버를 열 수 없습니다");
            return;
        }
        BluetoothGattService service = new BluetoothGattService(
                SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY);
        notifyCharacteristic = new BluetoothGattCharacteristic(
                NOTIFY_UUID,
                BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ);
        BluetoothGattDescriptor ccc = new BluetoothGattDescriptor(
                CCC_UUID,
                BluetoothGattDescriptor.PERMISSION_READ | BluetoothGattDescriptor.PERMISSION_WRITE);
        notifyCharacteristic.addDescriptor(ccc);
        service.addCharacteristic(notifyCharacteristic);
        if (!gattServer.addService(service)) {
            listener.onTransportError("BLE", "BLE 서비스를 등록할 수 없습니다");
            return;
        }
        BluetoothAdapter adapter = manager.getAdapter();
        advertiser = adapter.getBluetoothLeAdvertiser();
        if (advertiser == null) {
            listener.onTransportError("BLE", "이 기기는 BLE 알림을 지원하지 않습니다");
            return;
        }
        AdvertiseSettings settings = new AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .setTimeout(0)
                .build();
        AdvertiseData data = new AdvertiseData.Builder()
                .addServiceUuid(new ParcelUuid(SERVICE_UUID))
                .setIncludeDeviceName(false)
                .build();
        advertiser.startAdvertising(settings, data, advertiseCallback);
    }

    void startHost() {
        if (!isAvailable()) {
            listener.onTransportError("BLE", "블루투스를 사용할 수 없습니다");
            return;
        }
        running = true;
        scanner = manager.getAdapter().getBluetoothLeScanner();
        if (scanner == null) {
            listener.onTransportError("BLE", "BLE 탐색을 시작할 수 없습니다");
            return;
        }
        ScanFilter filter = new ScanFilter.Builder().setServiceUuid(new ParcelUuid(SERVICE_UUID)).build();
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        scanner.startScan(Collections.singletonList(filter), settings, scanCallback);
    }

    void sendFromGuest(BoyisoEvent event) {
        if (!running || gattServer == null || notifyCharacteristic == null) return;
        try {
            byte[] encrypted = codec.sealEvent(event);
            synchronized (notificationQueue) {
                synchronized (subscribedHosts) {
                    for (BluetoothDevice device : subscribedHosts) {
                        int mtu = negotiatedMtu.getOrDefault(device.getAddress(), 23);
                        List<byte[]> frames = BleFrames.fragment(encrypted,
                                Math.max(20, Math.min(MAX_FRAME_BYTES, mtu - 3)));
                        for (byte[] frame : frames) notificationQueue.add(new NotificationTask(device, frame));
                    }
                }
                while (notificationQueue.size() > 1_024) notificationQueue.poll();
                sendNextNotificationLocked();
            }
        } catch (GeneralSecurityException error) {
            listener.onTransportError("BLE", "암호화 실패");
        }
    }

    private final AdvertiseCallback advertiseCallback = new AdvertiseCallback() {
        @Override public void onStartFailure(int errorCode) {
            listener.onTransportError("BLE", "BLE 알림 시작 실패 " + errorCode);
        }
    };

    private final BluetoothGattServerCallback serverCallback = new BluetoothGattServerCallback() {
        @Override public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED && subscribedHosts.remove(device)) {
                negotiatedMtu.remove(device.getAddress());
                listener.onPathCount("BLE", subscribedHosts.size());
            }
        }

        @Override public void onMtuChanged(BluetoothDevice device, int mtu) {
            negotiatedMtu.put(device.getAddress(), Math.max(23, mtu));
        }

        @Override public void onDescriptorWriteRequest(BluetoothDevice device, int requestId,
                                                        BluetoothGattDescriptor descriptor,
                                                        boolean preparedWrite, boolean responseNeeded,
                                                        int offset, byte[] value) {
            boolean enabled = CCC_UUID.equals(descriptor.getUuid())
                    && java.util.Arrays.equals(value, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            if (enabled) subscribedHosts.add(device); else subscribedHosts.remove(device);
            if (responseNeeded && gattServer != null) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value);
            }
            listener.onPathCount("BLE", subscribedHosts.size());
        }

        @Override public void onCharacteristicReadRequest(BluetoothDevice device, int requestId,
                                                           int offset,
                                                           BluetoothGattCharacteristic characteristic) {
            if (gattServer != null) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, new byte[0]);
            }
        }

        @Override public void onNotificationSent(BluetoothDevice device, int status) {
            synchronized (notificationQueue) {
                notificationInFlight = false;
                sendNextNotificationLocked();
            }
        }
    };

    private void sendNextNotificationLocked() {
        if (notificationInFlight || gattServer == null || notifyCharacteristic == null) return;
        NotificationTask task = notificationQueue.poll();
        if (task == null) return;
        boolean started;
        if (Build.VERSION.SDK_INT >= 33) {
            started = gattServer.notifyCharacteristicChanged(task.device, notifyCharacteristic,
                    false, task.value) == android.bluetooth.BluetoothStatusCodes.SUCCESS;
        } else {
            notifyCharacteristic.setValue(task.value);
            started = gattServer.notifyCharacteristicChanged(task.device, notifyCharacteristic, false);
        }
        notificationInFlight = started;
        if (!started) sendNextNotificationLocked();
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override public void onScanResult(int callbackType, ScanResult result) {
            connectGuest(result.getDevice());
        }
        @Override public void onBatchScanResults(List<ScanResult> results) {
            for (ScanResult result : results) connectGuest(result.getDevice());
        }
        @Override public void onScanFailed(int errorCode) {
            listener.onTransportError("BLE", "BLE 탐색 실패 " + errorCode);
        }
    };

    private void connectGuest(BluetoothDevice device) {
        String address = device.getAddress();
        synchronized (guestGatts) {
            if (guestGatts.containsKey(address)) return;
            BluetoothGatt gatt = device.connectGatt(context, false, clientCallback,
                    BluetoothDevice.TRANSPORT_LE);
            if (gatt != null) {
                guestGatts.put(address, gatt);
                reassemblers.put(address, new BleFrames.Reassembler());
            }
        }
    }

    private final BluetoothGattCallback clientCallback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            String address = gatt.getDevice().getAddress();
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.requestMtu(REQUESTED_MTU);
                gatt.discoverServices();
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                readyGuests.remove(address);
                guestGatts.remove(address);
                reassemblers.remove(address);
                gatt.close();
                listener.onPathCount("BLE", readyGuests.size());
            }
        }

        @Override public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) return;
            BluetoothGattService service = gatt.getService(SERVICE_UUID);
            BluetoothGattCharacteristic characteristic = service == null ? null : service.getCharacteristic(NOTIFY_UUID);
            if (characteristic == null || !gatt.setCharacteristicNotification(characteristic, true)) return;
            BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CCC_UUID);
            if (descriptor == null) return;
            if (Build.VERSION.SDK_INT >= 33) {
                gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            } else {
                descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                gatt.writeDescriptor(descriptor);
            }
        }

        @Override public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS && CCC_UUID.equals(descriptor.getUuid())) {
                readyGuests.add(gatt.getDevice().getAddress());
                listener.onPathCount("BLE", readyGuests.size());
            }
        }

        @Override public void onCharacteristicChanged(BluetoothGatt gatt,
                                                       BluetoothGattCharacteristic characteristic,
                                                       byte[] value) {
            acceptBleFrame(gatt, value);
        }

        @Override public void onCharacteristicChanged(BluetoothGatt gatt,
                                                       BluetoothGattCharacteristic characteristic) {
            acceptBleFrame(gatt, characteristic.getValue());
        }
    };

    private void acceptBleFrame(BluetoothGatt gatt, byte[] frame) {
        BleFrames.Reassembler reassembler = reassemblers.get(gatt.getDevice().getAddress());
        if (reassembler == null) return;
        byte[] payload = reassembler.accept(frame, System.currentTimeMillis());
        if (payload == null) return;
        try {
            listener.onEvent(codec.openEvent(payload), "BLE");
        } catch (GeneralSecurityException | RuntimeException | org.json.JSONException ignored) {
            // Nearby Boyiso rooms use the same service UUID and are ignored if decryption fails.
        }
    }

    void stop() {
        running = false;
        if (advertiser != null) {
            try { advertiser.stopAdvertising(advertiseCallback); } catch (RuntimeException ignored) { }
        }
        if (scanner != null) {
            try { scanner.stopScan(scanCallback); } catch (RuntimeException ignored) { }
        }
        synchronized (guestGatts) {
            for (BluetoothGatt gatt : guestGatts.values()) {
                try { gatt.disconnect(); gatt.close(); } catch (RuntimeException ignored) { }
            }
            guestGatts.clear();
        }
        if (gattServer != null) {
            try { gattServer.clearServices(); gattServer.close(); } catch (RuntimeException ignored) { }
        }
        subscribedHosts.clear();
        negotiatedMtu.clear();
        readyGuests.clear();
        synchronized (notificationQueue) { notificationQueue.clear(); }
    }

    private static final class NotificationTask {
        final BluetoothDevice device;
        final byte[] value;
        NotificationTask(BluetoothDevice device, byte[] value) {
            this.device = device;
            this.value = value;
        }
    }
}
