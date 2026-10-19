package br.com.unitymob.field;

import static org.junit.Assert.*;

import android.app.AlertDialog;
import android.content.Context;
import android.content.res.TypedArray;
import android.view.ContextThemeWrapper;
import android.view.View;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class SelectDialogTest {
    @Test
    public void nativeOptionsDoNotInheritSplashBackground() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
            Context context = new ContextThemeWrapper(app, R.style.AppTheme_NoActionBar);
            AlertDialog dialog = new AlertDialog.Builder(context)
                .setSingleChoiceItems(new String[]{"Desocupado", "Inquilino", "Proprietário"}, 0, null)
                .create();
            dialog.create();
            assertEquals(3, dialog.getListView().getAdapter().getCount());
            View option = dialog.getListView().getAdapter().getView(0, null, dialog.getListView());
            TypedArray attributes = option.getContext().obtainStyledAttributes(
                new int[]{android.R.attr.background, android.R.attr.windowBackground});
            try {
                assertNotEquals(R.drawable.splash, attributes.getResourceId(0, 0));
                assertNotEquals(R.drawable.splash, attributes.getResourceId(1, 0));
            } finally {
                attributes.recycle();
                dialog.dismiss();
            }
        });
    }
}
