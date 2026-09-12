package br.com.unitymob.field;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import com.google.firebase.messaging.RemoteMessage;
import io.capawesome.capacitorjs.plugins.firebase.messaging.MessagingService;

public class NotificationService extends MessagingService {
    static void createChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        String[][] channels = {
            {"distribution", "Rodízio e leads atribuídos"}, {"pool", "Bolsão"},
            {"reminder", "Lembretes de tarefas e visitas"}, {"general", "Avisos gerais"}
        };
        AudioAttributes attributes = new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
        for (String[] entry : channels) {
            String id = "unitymob_" + entry[0] + "_v1";
            NotificationChannel channel = new NotificationChannel(id, entry[1], NotificationManager.IMPORTANCE_HIGH);
            channel.setSound(soundUri(context, id), attributes);
            manager.createNotificationChannel(channel); // Preserva as preferências de canais existentes.
        }
    }

    private static Uri soundUri(Context context, String sound) {
        return Uri.parse("android.resource://" + context.getPackageName() + "/raw/" + sound);
    }

    @Override
    public void onMessageReceived(RemoteMessage message) {
        super.onMessageReceived(message); // Mantém os eventos do plugin Capacitor.
        RemoteMessage.Notification notification = message.getNotification();
        if (notification == null) return;
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) return;
        createChannels(this);
        String channel = notification.getChannelId();
        if (channel == null || !channel.matches("unitymob_(distribution|pool|reminder|general)_v1")) {
            channel = "unitymob_general_v1";
        }
        String messageId = message.getMessageId();
        if (messageId == null) messageId = java.util.UUID.randomUUID().toString();
        Intent intent = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        for (java.util.Map.Entry<String, String> entry : message.getData().entrySet()) {
            intent.putExtra(entry.getKey(), entry.getValue());
        }
        intent.putExtra("google.message_id", messageId);
        PendingIntent tap = PendingIntent.getActivity(this, messageId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(notification.getTitle()).setContentText(notification.getBody())
            .setPriority(NotificationCompat.PRIORITY_HIGH).setSound(soundUri(this, channel))
            .setAutoCancel(true).setContentIntent(tap);
        // FCM mostra notification messages em background; este callback cobre o foreground.
        manager.notify(messageId, 0, builder.build());
    }
}
