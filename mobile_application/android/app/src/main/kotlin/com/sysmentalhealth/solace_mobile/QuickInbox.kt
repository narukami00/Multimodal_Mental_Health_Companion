package com.sysmentalhealth.solace_mobile

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Check-ins typed in the home-screen pop-up, held until the app is open.
 *
 * The app, not this file, saves them as entries (with its safety check and everything else a typed check-in gets).
 * This only keeps the words in the app's private storage and hands them over once.
 */
object QuickInbox {
    private const val FILE = "solace_quick_inbox"
    private const val KEY = "pending"

    @Synchronized
    fun add(context: Context, text: String) {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val list = try {
            JSONArray(prefs.getString(KEY, "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        list.put(JSONObject().put("text", text).put("at", System.currentTimeMillis()))
        prefs.edit().putString(KEY, list.toString()).apply()
    }

    /** Everything waiting, oldest first, emptied as it is taken. */
    @Synchronized
    fun drain(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        val out = ArrayList<Map<String, Any>>()
        try {
            val list = JSONArray(raw)
            for (i in 0 until list.length()) {
                val item = list.getJSONObject(i)
                out.add(mapOf("text" to item.getString("text"), "at" to item.getLong("at")))
            }
        } catch (e: Exception) {
            // A damaged file is dropped rather than kept to fail forever.
        }
        prefs.edit().remove(KEY).apply()
        return out
    }
}
