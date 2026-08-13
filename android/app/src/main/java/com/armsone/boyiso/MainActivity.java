package com.armsone.boyiso;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.security.SecureRandom;
import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int PERMISSION_REQUEST = 41;
    private static final int BACKGROUND = Color.rgb(247, 244, 238);
    private static final int INK = Color.rgb(31, 45, 41);
    private static final int ACCENT = Color.rgb(49, 92, 82);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout root;
    private RadioButton hostButton;
    private RadioButton guestButton;
    private EditText roomCode;
    private TextView connectionStatus;
    private TextView monitoringStatus;
    private TextView eventStatus;
    private TextView permissionStatus;
    private Button startStopButton;
    private boolean receiverRegistered;
    private boolean pendingStart;

    private final BroadcastReceiver updates = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (MonitoringService.ACTION_STATE.equals(intent.getAction())) renderState(intent);
            else if (MonitoringService.ACTION_EVENT.equals(intent.getAction())) renderEvent(intent);
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setTitle("보이소");
        buildInterface();
        restoreConfiguration();
        renderPermissions();
    }

    @Override protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter();
        filter.addAction(MonitoringService.ACTION_STATE);
        filter.addAction(MonitoringService.ACTION_EVENT);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(updates, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(updates, filter);
        receiverRegistered = true;
        renderRunning(MonitoringService.isActive);
    }

    @Override protected void onStop() {
        if (receiverRegistered) {
            unregisterReceiver(updates);
            receiverRegistered = false;
        }
        super.onStop();
    }

    private void buildInterface() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(28), dp(24), dp(32));
        root.setBackgroundColor(BACKGROUND);
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));

        TextView title = text("보이소", 38, Typeface.BOLD);
        title.setLetterSpacing(-0.02f);
        root.addView(title);
        TextView subtitle = text("보이는 소리", 18, Typeface.NORMAL);
        subtitle.setTextColor(ACCENT);
        root.addView(subtitle, margins(0, 2, 0, 24));

        TextView mission = text("들리지 않아 놓칠 수 있는 큰 소리와 지속 소리를, 가까운 화면의 빛과 상태로 전합니다.",
                16, Typeface.NORMAL);
        mission.setLineSpacing(0, 1.2f);
        root.addView(mission, margins(0, 0, 0, 28));

        root.addView(sectionLabel("이 기기의 역할"));
        RadioGroup roles = new RadioGroup(this);
        roles.setOrientation(LinearLayout.HORIZONTAL);
        hostButton = radio("호스트 · 돌보는 사람");
        guestButton = radio("게스트 · 아이 곁");
        roles.addView(hostButton, new RadioGroup.LayoutParams(0, dp(52), 1));
        roles.addView(guestButton, new RadioGroup.LayoutParams(0, dp(52), 1));
        hostButton.setChecked(true);
        root.addView(roles, margins(0, 8, 0, 22));

        root.addView(sectionLabel("함께 사용할 방 코드"));
        LinearLayout codeRow = new LinearLayout(this);
        codeRow.setOrientation(LinearLayout.HORIZONTAL);
        codeRow.setGravity(Gravity.CENTER_VERTICAL);
        roomCode = new EditText(this);
        roomCode.setSingleLine(true);
        roomCode.setTextSize(22);
        roomCode.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        roomCode.setGravity(Gravity.CENTER);
        roomCode.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        roomCode.setFilters(new InputFilter[]{new InputFilter.AllCaps(Locale.ROOT), new InputFilter.LengthFilter(8)});
        roomCode.setContentDescription("영문과 숫자 8자리 방 코드");
        Button copy = secondaryButton("복사");
        copy.setOnClickListener(view -> copyRoomCode());
        codeRow.addView(roomCode, new LinearLayout.LayoutParams(0, dp(58), 1));
        codeRow.addView(copy, new LinearLayout.LayoutParams(dp(76), dp(52)));
        root.addView(codeRow, margins(0, 8, 0, 6));
        TextView codeHelp = text("두 기기에 같은 코드를 입력하세요. 코드는 연결 암호화 키로 사용됩니다.", 13, Typeface.NORMAL);
        codeHelp.setTextColor(Color.rgb(91, 99, 96));
        root.addView(codeHelp, margins(0, 0, 0, 24));

        LinearLayout statusCard = card();
        TextView statusTitle = text("돌봄 상태", 17, Typeface.BOLD);
        statusCard.addView(statusTitle);
        connectionStatus = text("Wi-Fi 0 · Bluetooth 0", 16, Typeface.NORMAL);
        statusCard.addView(connectionStatus, margins(0, 10, 0, 4));
        monitoringStatus = text("감시를 시작하지 않았습니다", 15, Typeface.NORMAL);
        monitoringStatus.setTextColor(Color.rgb(91, 99, 96));
        statusCard.addView(monitoringStatus);
        eventStatus = text("아직 전달된 소리가 없습니다", 15, Typeface.BOLD);
        eventStatus.setTextColor(ACCENT);
        statusCard.addView(eventStatus, margins(0, 18, 0, 0));
        root.addView(statusCard, margins(0, 0, 0, 18));

        permissionStatus = text("", 13, Typeface.NORMAL);
        permissionStatus.setTextColor(Color.rgb(91, 99, 96));
        root.addView(permissionStatus, margins(0, 0, 0, 14));

        startStopButton = new Button(this);
        startStopButton.setText("돌봄 연결 시작");
        startStopButton.setTextSize(17);
        startStopButton.setTextColor(Color.WHITE);
        startStopButton.setBackgroundColor(ACCENT);
        startStopButton.setOnClickListener(view -> toggleMonitoring());
        root.addView(startStopButton, new LinearLayout.LayoutParams(-1, dp(58)));

        TextView safety = text("보이소는 의료기기나 보호자의 직접 확인을 대신하지 않습니다. 연결이 끊기면 화면에 분명히 표시됩니다.",
                12, Typeface.NORMAL);
        safety.setTextColor(Color.rgb(105, 105, 105));
        safety.setGravity(Gravity.CENTER);
        root.addView(safety, margins(0, 18, 0, 0));
        setContentView(scroll);
    }

    private void restoreConfiguration() {
        String saved = getSharedPreferences("boyiso", MODE_PRIVATE).getString("room_code", null);
        if (saved == null || saved.length() != 8) saved = generateRoomCode();
        roomCode.setText(saved);
        String role = getSharedPreferences("boyiso", MODE_PRIVATE).getString("role", MonitoringService.ROLE_HOST);
        guestButton.setChecked(MonitoringService.ROLE_GUEST.equals(role));
        hostButton.setChecked(!guestButton.isChecked());
    }

    private void toggleMonitoring() {
        if (MonitoringService.isActive) {
            Intent stop = new Intent(this, MonitoringService.class).setAction(MonitoringService.ACTION_STOP);
            startService(stop);
            return;
        }
        String normalized = roomCode.getText().toString().replaceAll("[^A-Za-z0-9]", "").toUpperCase(Locale.ROOT);
        if (normalized.length() != 8) {
            roomCode.setError("영문과 숫자 8자리를 입력하세요");
            return;
        }
        roomCode.setText(normalized);
        pendingStart = true;
        requestNeededPermissions();
    }

    private void requestNeededPermissions() {
        List<String> missing = new ArrayList<>();
        if (guestButton.isChecked() && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.RECORD_AUDIO);
        }
        if (Build.VERSION.SDK_INT >= 31) {
            addIfMissing(missing, Manifest.permission.BLUETOOTH_SCAN);
            addIfMissing(missing, Manifest.permission.BLUETOOTH_CONNECT);
            if (guestButton.isChecked()) addIfMissing(missing, Manifest.permission.BLUETOOTH_ADVERTISE);
        } else {
            addIfMissing(missing, Manifest.permission.ACCESS_FINE_LOCATION);
        }
        if (Build.VERSION.SDK_INT >= 33) addIfMissing(missing, Manifest.permission.POST_NOTIFICATIONS);
        if (missing.isEmpty()) startMonitoring();
        else requestPermissions(missing.toArray(new String[0]), PERMISSION_REQUEST);
    }

    private void addIfMissing(List<String> values, String permission) {
        if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) values.add(permission);
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        renderPermissions();
        if (requestCode == PERMISSION_REQUEST && pendingStart) {
            if (guestButton.isChecked()
                    && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                pendingStart = false;
                permissionStatus.setText("아이 곁 모드에는 마이크 권한이 필요합니다. 권한을 허용한 뒤 다시 시작하세요.");
            } else {
                startMonitoring();
            }
        }
    }

    private void startMonitoring() {
        pendingStart = false;
        String role = guestButton.isChecked() ? MonitoringService.ROLE_GUEST : MonitoringService.ROLE_HOST;
        String code = roomCode.getText().toString();
        getSharedPreferences("boyiso", MODE_PRIVATE).edit()
                .putString("role", role).putString("room_code", code).apply();
        Intent start = new Intent(this, MonitoringService.class)
                .setAction(MonitoringService.ACTION_START)
                .putExtra(MonitoringService.EXTRA_ROLE, role)
                .putExtra(MonitoringService.EXTRA_ROOM_CODE, code);
        startForegroundService(start);
        renderRunning(true);
    }

    private void renderState(Intent intent) {
        boolean running = intent.getBooleanExtra("running", false);
        int lan = intent.getIntExtra("lanCount", 0);
        int ble = intent.getIntExtra("bleCount", 0);
        int guests = intent.getIntExtra("guestCount", 0);
        boolean monitoring = intent.getBooleanExtra("monitoring", false);
        String stateRole = intent.getStringExtra("role");
        String error = intent.getStringExtra("error");
        connectionStatus.setText("Wi-Fi " + lan + " · Bluetooth " + ble);
        if (!running) monitoringStatus.setText("감시를 시작하지 않았습니다");
        else if (MonitoringService.ROLE_GUEST.equals(stateRole)) {
            monitoringStatus.setText(monitoring ? "아이 곁 소리를 살피는 중" : "마이크 감시가 중단됨");
        } else if (guests == 0) {
            monitoringStatus.setText("연결된 아이 곁 기기가 없습니다");
        } else {
            monitoringStatus.setText(guests + "대의 아이 곁 기기를 확인 중");
        }
        if (error != null && !error.isEmpty()) monitoringStatus.setText(error);
        renderRunning(running);
    }

    private void renderEvent(Intent intent) {
        String detail = intent.getStringExtra("detail");
        String source = intent.getStringExtra("sourceName");
        String path = intent.getStringExtra("path");
        long timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis());
        String label = BoyisoEvent.DETAIL_CONTINUOUS_SOUND.equals(detail) ? "지속되는 소리" : "큰 소리";
        String time = DateFormat.getTimeInstance(DateFormat.SHORT).format(new Date(timestamp));
        eventStatus.setText(label + " · " + source + " · " + time + "\n" + path + "로 확인");
        flashScreen();
    }

    private void renderRunning(boolean running) {
        startStopButton.setText(running ? "돌봄 연결 중지" : "돌봄 연결 시작");
        hostButton.setEnabled(!running);
        guestButton.setEnabled(!running);
        roomCode.setEnabled(!running);
        if (running) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    private void renderPermissions() {
        boolean microphone = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
        boolean bluetooth = Build.VERSION.SDK_INT < 31
                || (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
                && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED);
        permissionStatus.setText("권한 · 마이크 " + (microphone ? "허용" : "필요")
                + " · Bluetooth " + (bluetooth ? "허용" : "필요")
                + " · Wi-Fi 별도 권한 없음");
    }

    private void flashScreen() {
        root.setBackgroundColor(Color.rgb(255, 248, 216));
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(() -> root.setBackgroundColor(BACKGROUND), 1_500);
    }

    private void copyRoomCode() {
        ((ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE))
                .setPrimaryClip(ClipData.newPlainText("보이소 방 코드", roomCode.getText().toString()));
        Toast.makeText(this, "방 코드를 복사했습니다", Toast.LENGTH_SHORT).show();
    }

    private String generateRoomCode() {
        final String alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        SecureRandom random = new SecureRandom();
        StringBuilder output = new StringBuilder(8);
        for (int index = 0; index < 8; index++) output.append(alphabet.charAt(random.nextInt(alphabet.length())));
        return output.toString();
    }

    private TextView text(String value, int sp, int style) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(INK);
        view.setTypeface(Typeface.create("sans", style));
        return view;
    }

    private TextView sectionLabel(String value) {
        TextView view = text(value, 14, Typeface.BOLD);
        view.setTextColor(Color.rgb(91, 99, 96));
        return view;
    }

    private RadioButton radio(String value) {
        RadioButton button = new RadioButton(this);
        button.setText(value);
        button.setTextSize(14);
        button.setTextColor(INK);
        button.setGravity(Gravity.CENTER_VERTICAL);
        return button;
    }

    private Button secondaryButton(String value) {
        Button button = new Button(this);
        button.setText(value);
        button.setTextColor(ACCENT);
        button.setTextSize(14);
        return button;
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(20), dp(20), dp(20), dp(20));
        android.graphics.drawable.GradientDrawable background = new android.graphics.drawable.GradientDrawable();
        background.setColor(Color.WHITE);
        background.setCornerRadius(dp(18));
        background.setStroke(dp(1), Color.rgb(226, 224, 218));
        card.setBackground(background);
        return card;
    }

    private LinearLayout.LayoutParams margins(int left, int top, int right, int bottom) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(left), dp(top), dp(right), dp(bottom));
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
