package com.cash.dash

import android.content.Context
import java.util.Locale

object CategoryIconHelper {

    private val foodKeywords = setOf("food", "foodie", "hotel", "soru", "lunch", "dinner", "breakfast", "restaurant", "swiggy", "zomato", "eat", "meal", "snack")
    private val shoppingKeywords = setOf("shop", "shopping", "cart", "buy", "mall", "clothes", "amazon", "flipkart", "myntra", "grocery", "groceries")
    private val fuelKeywords = setOf("petrol", "diesel", "fuel", "gas", "cng", "pump")
    private val transportKeywords = setOf("travel", "bus", "car", "train", "flight", "taxi", "cab", "uber", "ola", "rapido", "auto", "metro", "transport")
    private val waterKeywords = setOf("water", "drinking", "aqua", "can", "bisleri")

    /** Where a user's explicit icon choice is stored, as a stable key. See [KEY_LEGACY_PREFIX]. */
    const val KEY_PREFIX = "ICONKEY_"

    /**
     * The old storage: a raw `R.drawable.*` integer.
     *
     * Resource IDs are assigned at build time and renumber whenever resources are added or
     * removed, so a stored ID silently starts pointing at a different drawable after any such
     * change — a category picked as "Transport" came back as a clock. Worse, these integers
     * were also synced to Firestore, so an ID minted by one build was restored onto another
     * build, and onto other devices, where it never meant anything at all.
     *
     * Values under this key can therefore never be trusted and are discarded on sight.
     */
    const val KEY_LEGACY_PREFIX = "ICON_"

    /** The six choices the icon picker offers. Keys are stable and safe to persist and sync. */
    private val keyToRes = mapOf(
        "food" to R.drawable.ic_category_food,
        "shopping" to R.drawable.ic_category_shopping,
        "fuel" to R.drawable.ic_category_fuel,
        "transport" to R.drawable.ic_category_transport,
        "water" to R.drawable.ic_category_water,
        "other" to R.drawable.ic_edit
    )
    private val resToKey = keyToRes.entries.associate { (k, v) -> v to k }

    /** The drawable a stored key refers to, or null if the key is unknown. */
    fun resForKey(key: String?): Int? = key?.let { keyToRes[it] }

    /** The key to persist for a chosen drawable. */
    fun keyForRes(resId: Int): String? = resToKey[resId]

    /**
     * Picks the icon for [categoryName]: the user's explicit choice if there is a trustworthy
     * one, otherwise a keyword match on the name, otherwise the pencil.
     */
    fun getIconForCategory(context: Context, categoryName: String): Int {
        val prefs = context.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)

        val chosen = resForKey(prefs.getString(KEY_PREFIX + categoryName, null))
        if (chosen != null) return chosen

        // A leftover resource ID from before keys existed. It cannot be mapped back to an
        // icon with any confidence, so drop it rather than render whatever it now points at,
        // and let the keyword match below produce something defensible instead.
        if (prefs.contains(KEY_LEGACY_PREFIX + categoryName)) {
            prefs.edit().remove(KEY_LEGACY_PREFIX + categoryName).apply()
        }

        val normalized = categoryName.lowercase(Locale.getDefault()).trim()

        // Whole-word matching, so "carnival" does not match "car".
        for (word in foodKeywords) {
            if (Regex("\\b$word\\b").containsMatchIn(normalized)) return R.drawable.ic_category_food
        }
        for (word in shoppingKeywords) {
            if (Regex("\\b$word\\b").containsMatchIn(normalized)) return R.drawable.ic_category_shopping
        }
        for (word in fuelKeywords) {
            if (Regex("\\b$word\\b").containsMatchIn(normalized)) return R.drawable.ic_category_fuel
        }
        for (word in transportKeywords) {
            if (Regex("\\b$word\\b").containsMatchIn(normalized)) return R.drawable.ic_category_transport
        }
        for (word in waterKeywords) {
            if (Regex("\\b$word\\b").containsMatchIn(normalized)) return R.drawable.ic_category_water
        }

        return R.drawable.ic_edit
    }
}
