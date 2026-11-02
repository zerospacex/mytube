package com.custom.ytadfree.adfree_youtube

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class BackgroundPlaybackService : Service() {
    companion object {
        var onCommand: ((String, Double?) -> Unit)? = null
        var isRunning = false
            private set
    }
    private lateinit var session: MediaSession
    private var wakeLock: PowerManager.WakeLock? = null
    private var background = false
    private var playing = false
    private var title = "MyTube Music"
    private var artist = ""
    private var notificationKey = ""
    private var metadataKey = ""

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        session = MediaSession(this, "MyTubeMusic").apply {
            setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { onCommand?.invoke("play", null) }
                override fun onPause() { onCommand?.invoke("pause", null) }
                override fun onSkipToNext() { onCommand?.invoke("next", null) }
                override fun onSkipToPrevious() { onCommand?.invoke("previous", null) }
                override fun onSeekTo(pos: Long) { onCommand?.invoke("seek", pos / 1000.0) }
            })
            isActive = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel("background_music", "Music playback", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    @SuppressLint("WakelockTimeout")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != null) {
            onCommand?.invoke(intent.action!!, null)
            return START_NOT_STICKY
        }
        if (intent?.hasExtra("background") == true) background = intent.getBooleanExtra("background", false)
        if (intent?.hasExtra("title") == true) {
            session.isActive = true
            title = intent.getStringExtra("title") ?: "MyTube Music"
            artist = intent.getStringExtra("artist") ?: ""
            playing = intent.getBooleanExtra("playing", false)
            val duration = intent.getLongExtra("duration", 0L).coerceAtLeast(0)
            val position = intent.getLongExtra("position", 0L).coerceAtLeast(0)
            val key = "$title\n$artist\n$duration"
            if (key != metadataKey) {
                session.setMetadata(MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, duration).build())
                metadataKey = key
            }
            session.setPlaybackState(PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                    PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_SEEK_TO)
                .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    position, if (playing) 1f else 0f).build())
        }
        if (background && playing && wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MyTubeMusic:Playback").apply { acquire() }
        } else if (!background || !playing) releaseWakeLock()
        val key = "$title\n$artist\n$playing"
        if (key != notificationKey) {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else startForeground(1, notification)
            notificationKey = key
        }
        return START_NOT_STICKY
    }

    private fun actionIntent(action: String, id: Int): PendingIntent = PendingIntent.getService(
        this, id, Intent(this, BackgroundPlaybackService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, "background_music")
                      else Notification.Builder(this)
        return builder.setContentTitle(title).setContentText(artist)
            .setSmallIcon(android.R.drawable.ic_media_play).setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(playing).setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_previous, "Previous", actionIntent("previous", 1))
            .addAction(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play", actionIntent(if (playing) "pause" else "play", 2))
            .addAction(android.R.drawable.ic_media_next, "Next", actionIntent("next", 3))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }
    override fun onDestroy() {
        releaseWakeLock()
        session.isActive = false
        session.release()
        isRunning = false
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
