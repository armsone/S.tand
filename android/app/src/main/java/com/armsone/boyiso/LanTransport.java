package com.armsone.boyiso;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

final class LanTransport {
    static final String SERVICE_TYPE = "_boyiso._tcp.";

    interface Listener {
        void onEvent(BoyisoEvent event, String path);
        void onPathCount(String path, int count);
        void onTransportError(String path, String message);
    }

    private final Context context;
    private final CryptoCodec codec;
    private final Listener listener;
    private final String sourceId;
    private final ExecutorService io = Executors.newCachedThreadPool();
    private final ScheduledExecutorService retry = Executors.newSingleThreadScheduledExecutor();
    private final Set<PeerWriter> guestClients = ConcurrentHashMap.newKeySet();
    private final Map<String, Endpoint> knownGuests = new ConcurrentHashMap<>();
    private final Map<String, Socket> hostSockets = new ConcurrentHashMap<>();
    private final ArrayDeque<NsdServiceInfo> resolutionQueue = new ArrayDeque<>();
    private boolean resolutionInProgress;
    private volatile boolean running;
    private ServerSocket serverSocket;
    private NsdManager.RegistrationListener registrationListener;
    private NsdManager.DiscoveryListener discoveryListener;

    LanTransport(Context context, CryptoCodec codec, String sourceId, Listener listener) {
        this.context = context.getApplicationContext();
        this.codec = codec;
        this.listener = listener;
        this.sourceId = sourceId;
    }

    void startGuest() {
        running = true;
        io.execute(() -> {
            try {
                serverSocket = new ServerSocket(0);
                registerGuest(serverSocket.getLocalPort());
                while (running) {
                    Socket socket = serverSocket.accept();
                    if (guestClients.size() >= 32) {
                        socket.close();
                        continue;
                    }
                    configure(socket);
                    PeerWriter peer = new PeerWriter(socket);
                    guestClients.add(peer);
                    listener.onPathCount("LAN", guestClients.size());
                    io.execute(() -> holdGuestClient(peer));
                }
            } catch (IOException error) {
                if (running) listener.onTransportError("LAN", error.getMessage());
            }
        });
    }

    void startHost() {
        running = true;
        discoverGuests();
        retry.scheduleWithFixedDelay(this::connectKnownGuests, 0, 5, TimeUnit.SECONDS);
    }

    void sendFromGuest(BoyisoEvent event) {
        if (!running) return;
        try {
            String frame = codec.sealToText(event);
            for (PeerWriter peer : guestClients) {
                try {
                    peer.write(frame);
                } catch (IOException error) {
                    removeGuestClient(peer);
                }
            }
        } catch (GeneralSecurityException error) {
            listener.onTransportError("LAN", "암호화 실패");
        }
    }

    private void registerGuest(int port) {
        NsdManager manager = (NsdManager) context.getSystemService(Context.NSD_SERVICE);
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName("Boyiso-" + sourceId.substring(0, Math.min(8, sourceId.length())));
        info.setServiceType(SERVICE_TYPE);
        info.setPort(port);
        registrationListener = new NsdManager.RegistrationListener() {
            @Override public void onServiceRegistered(NsdServiceInfo serviceInfo) { }
            @Override public void onRegistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                listener.onTransportError("LAN", "서비스 알림 실패 " + errorCode);
            }
            @Override public void onServiceUnregistered(NsdServiceInfo serviceInfo) { }
            @Override public void onUnregistrationFailed(NsdServiceInfo serviceInfo, int errorCode) { }
        };
        manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, registrationListener);
    }

    private void discoverGuests() {
        NsdManager manager = (NsdManager) context.getSystemService(Context.NSD_SERVICE);
        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String serviceType) { }
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                listener.onTransportError("LAN", "탐색 시작 실패 " + errorCode);
            }
            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) { }
            @Override public void onDiscoveryStopped(String serviceType) { }
            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                if (!serviceInfo.getServiceType().equals(SERVICE_TYPE)) return;
                enqueueResolution(manager, serviceInfo);
            }
            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {
                Endpoint endpoint = knownGuests.remove(serviceInfo.getServiceName());
                if (endpoint != null) closeHostSocket(endpoint.key);
            }
        };
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener);
    }

    private void enqueueResolution(NsdManager manager, NsdServiceInfo info) {
        synchronized (resolutionQueue) {
            boolean alreadyQueued = false;
            for (NsdServiceInfo queued : resolutionQueue) {
                if (queued.getServiceName().equals(info.getServiceName())) alreadyQueued = true;
            }
            if (!knownGuests.containsKey(info.getServiceName()) && !alreadyQueued) {
                resolutionQueue.add(info);
            }
            resolveNextLocked(manager);
        }
    }

    private void resolveNextLocked(NsdManager manager) {
        if (resolutionInProgress || resolutionQueue.isEmpty() || !running) return;
        NsdServiceInfo next = resolutionQueue.poll();
        resolutionInProgress = true;
        try {
            manager.resolveService(next, new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo info, int errorCode) {
                    finishResolution(manager);
                }
                @Override public void onServiceResolved(NsdServiceInfo info) {
                    InetAddress host = info.getHost();
                    if (host != null && info.getPort() > 0) {
                        knownGuests.put(info.getServiceName(),
                                new Endpoint(info.getServiceName(), host, info.getPort()));
                        connectKnownGuests();
                    }
                    finishResolution(manager);
                }
            });
        } catch (RuntimeException error) {
            resolutionInProgress = false;
            resolveNextLocked(manager);
        }
    }

    private void finishResolution(NsdManager manager) {
        synchronized (resolutionQueue) {
            resolutionInProgress = false;
            resolveNextLocked(manager);
        }
    }

    private void connectKnownGuests() {
        if (!running) return;
        for (Endpoint endpoint : knownGuests.values()) {
            if (!hostSockets.containsKey(endpoint.key)) io.execute(() -> connectHost(endpoint));
        }
    }

    private void connectHost(Endpoint endpoint) {
        if (!running || hostSockets.containsKey(endpoint.key)) return;
        Socket socket = new Socket();
        try {
            socket.connect(new java.net.InetSocketAddress(endpoint.host, endpoint.port), 3_000);
            configure(socket);
            Socket existing = hostSockets.putIfAbsent(endpoint.key, socket);
            if (existing != null) {
                socket.close();
                return;
            }
            listener.onPathCount("LAN", hostSockets.size());
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    socket.getInputStream(), StandardCharsets.UTF_8));
            String line;
            while (running && (line = reader.readLine()) != null) {
                if (line.length() > 16_384) continue;
                try {
                    listener.onEvent(codec.openText(line), "LAN");
                } catch (GeneralSecurityException | RuntimeException | org.json.JSONException ignored) {
                    // Other Boyiso rooms can be present on the same LAN; they are intentionally ignored.
                }
            }
        } catch (IOException error) {
            // Retry loop reconnects while NSD still reports this guest.
        } finally {
            closeHostSocket(endpoint.key);
        }
    }

    private void holdGuestClient(PeerWriter peer) {
        try {
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    peer.socket.getInputStream(), StandardCharsets.UTF_8));
            while (running && reader.readLine() != null) { }
        } catch (IOException ignored) {
        } finally {
            removeGuestClient(peer);
        }
    }

    private static void configure(Socket socket) throws IOException {
        socket.setKeepAlive(true);
        socket.setTcpNoDelay(true);
    }

    private void removeGuestClient(PeerWriter peer) {
        if (guestClients.remove(peer)) {
            peer.close();
            listener.onPathCount("LAN", guestClients.size());
        }
    }

    private void closeHostSocket(String key) {
        Socket socket = hostSockets.remove(key);
        if (socket != null) {
            try { socket.close(); } catch (IOException ignored) { }
            listener.onPathCount("LAN", hostSockets.size());
        }
    }

    void stop() {
        running = false;
        NsdManager manager = (NsdManager) context.getSystemService(Context.NSD_SERVICE);
        if (registrationListener != null) {
            try { manager.unregisterService(registrationListener); } catch (RuntimeException ignored) { }
        }
        if (discoveryListener != null) {
            try { manager.stopServiceDiscovery(discoveryListener); } catch (RuntimeException ignored) { }
        }
        try { if (serverSocket != null) serverSocket.close(); } catch (IOException ignored) { }
        for (PeerWriter peer : guestClients) peer.close();
        guestClients.clear();
        for (String key : hostSockets.keySet()) closeHostSocket(key);
        retry.shutdownNow();
        io.shutdownNow();
    }

    private static final class Endpoint {
        final String key;
        final InetAddress host;
        final int port;
        Endpoint(String key, InetAddress host, int port) {
            this.key = key;
            this.host = host;
            this.port = port;
        }
    }

    private static final class PeerWriter {
        final Socket socket;
        final BufferedWriter writer;
        PeerWriter(Socket socket) throws IOException {
            this.socket = socket;
            writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8));
        }
        synchronized void write(String frame) throws IOException {
            writer.write(frame);
            writer.newLine();
            writer.flush();
        }
        void close() {
            try { socket.close(); } catch (IOException ignored) { }
        }
    }
}
