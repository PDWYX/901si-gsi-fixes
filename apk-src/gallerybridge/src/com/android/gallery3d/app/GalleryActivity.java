package com.android.gallery3d.app;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * 原厂相机点缩略图时会硬编码启动：
 *   {org.codeaurora.gallery/com.android.gallery3d.app.GalleryActivity}
 *
 * 原厂 SnapdragonGallery 与 GSI 自带的 Gallery2 权限冲突，装不上。
 * 这个转接包只占住包名和 Activity 名，把收到的 Intent 原样转给
 * 系统 Gallery2（com.android.gallery3d/.app.GalleryActivity）。
 */
public class GalleryActivity extends Activity {
    private static final int REQ = 1;
    private static final String TAG = "GalleryBridge";
    private static final ComponentName TARGET = new ComponentName(
            "com.android.gallery3d", "com.android.gallery3d.app.GalleryActivity");

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent intent = getIntent();
        intent = (intent == null) ? new Intent() : new Intent(intent);
        intent.setComponent(TARGET);
        Log.i(TAG, "forwarding to Gallery2: " + intent);
        try {
            startActivityForResult(intent, REQ);
        } catch (Exception e) {
            Log.e(TAG, "failed: " + e);
            finish();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        setResult(resultCode, data);
        finish();
    }
}
