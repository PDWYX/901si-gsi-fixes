package com.dsh.eventlogstub;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

/**
 * 原厂相机启动时会往 content://com.ssol.eventlog/eventlog 写一条事件。
 * 原厂 provider 属于 /priv-app/EventLog（OEM 平台签名），GSI 上没有，
 * 于是相机在 MainActivity.onCreate 直接崩溃。
 *
 * 这个替身只负责接住写入并返回一个 Uri；不保存任何内容。
 */
public class EventLogProvider extends ContentProvider {
    private static final String TAG = "EventLogStub";
    private static final Uri BASE = Uri.parse("content://com.ssol.eventlog/eventlog");

    @Override
    public boolean onCreate() {
        Log.i(TAG, "stub provider created");
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        Log.i(TAG, "query " + uri);
        return new MatrixCursor(new String[]{"_id"}, 0);
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        Log.i(TAG, "insert " + uri + " " + values);
        return Uri.withAppendedPath(BASE, "1");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        Log.i(TAG, "delete " + uri);
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        Log.i(TAG, "update " + uri);
        return 0;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        Log.i(TAG, "call " + method);
        return new Bundle();
    }
}
