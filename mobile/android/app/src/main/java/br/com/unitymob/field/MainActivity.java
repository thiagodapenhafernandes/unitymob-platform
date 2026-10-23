package br.com.unitymob.field;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(android.os.Bundle savedInstanceState) {
        registerPlugin(WhatsappLinksPlugin.class);
        super.onCreate(savedInstanceState);
        NotificationService.createChannels(this);
    }
}
