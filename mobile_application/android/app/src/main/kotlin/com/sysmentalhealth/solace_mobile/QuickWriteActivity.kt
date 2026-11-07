package com.sysmentalhealth.solace_mobile

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.Toast

/**
 * The small pop-up the home-screen widget opens: a text box and a save button, over whatever the person was doing.
 * The words go to [QuickInbox]; the app saves them as a check-in the next time it is open.
 */
class QuickWriteActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.quick_write)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)

        val input = findViewById<EditText>(R.id.quick_input)
        val save = findViewById<Button>(R.id.quick_save)
        findViewById<Button>(R.id.quick_cancel).setOnClickListener { finish() }
        save.setOnClickListener {
            val text = input.text.toString().trim()
            if (text.isEmpty()) {
                finish()
                return@setOnClickListener
            }
            QuickInbox.add(this, text.take(1000))
            Toast.makeText(this, R.string.quick_write_saved, Toast.LENGTH_SHORT).show()
            finish()
        }
    }
}
