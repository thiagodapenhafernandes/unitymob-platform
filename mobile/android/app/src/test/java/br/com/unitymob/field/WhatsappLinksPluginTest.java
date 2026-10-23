package br.com.unitymob.field;

import static org.junit.Assert.*;
import org.junit.Test;

public class WhatsappLinksPluginTest {
    @Test
    public void handlesOnlyWhatsappDestinations() {
        assertTrue(WhatsappLinksPlugin.handles("https://wa.me/?text=Apartamento"));
        assertTrue(WhatsappLinksPlugin.handles("whatsapp://send/?text=Apartamento"));
        assertTrue(WhatsappLinksPlugin.handles("https://api.whatsapp.com/send?phone=554700000000"));
        assertFalse(WhatsappLinksPlugin.handles("https://wa.me.attacker.test/"));
        assertFalse(WhatsappLinksPlugin.handles("https://saluteimoveis.com.br/admin"));
        assertFalse(WhatsappLinksPlugin.handles("javascript:alert(1)"));
        assertFalse(WhatsappLinksPlugin.handles("invalid url"));
    }

    @Test
    public void preservesEncodedMessageAndPhoneInBrowserFallback() {
        assertEquals("https://api.whatsapp.com/send/?phone=554700000000&text=Ol%C3%A1%20%26%20teste",
            WhatsappLinksPlugin.browserFallback("whatsapp://send/?phone=554700000000&text=Ol%C3%A1%20%26%20teste"));
    }
}
