package br.com.unitymob.field;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.widget.Toast;
import com.getcapacitor.Plugin;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.net.URI;
import java.util.Locale;

@CapacitorPlugin(name = "WhatsappLinks")
public class WhatsappLinksPlugin extends Plugin {
    static boolean handles(String value) {
        try {
            URI uri = URI.create(value);
            String scheme = String.valueOf(uri.getScheme()).toLowerCase(Locale.ROOT);
            String host = String.valueOf(uri.getHost()).toLowerCase(Locale.ROOT);
            return scheme.equals("whatsapp") ||
                ((scheme.equals("https") || scheme.equals("http")) &&
                    (host.equals("wa.me") || host.equals("api.whatsapp.com") || host.equals("web.whatsapp.com")));
        } catch (IllegalArgumentException error) {
            return false;
        }
    }

    static String browserFallback(String value) {
        URI uri = URI.create(value);
        return "https://api.whatsapp.com/send/?" + (uri.getRawQuery() == null ? "" : uri.getRawQuery());
    }

    @Override
    public Boolean shouldOverrideLoad(Uri url) {
        if (!handles(url.toString())) return null;
        try {
            getActivity().startActivity(new Intent(Intent.ACTION_VIEW, url));
        } catch (ActivityNotFoundException error) {
            try {
                getActivity().startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(browserFallback(url.toString()))));
            } catch (ActivityNotFoundException unavailable) {
                Toast.makeText(getContext(), "Não foi possível abrir o WhatsApp. Use Copiar link para compartilhar.", Toast.LENGTH_LONG).show();
            }
        }
        return true;
    }
}
