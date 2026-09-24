package com.cash.dash

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

data class RigorCategoryItem(
    val name: String,
    val limit: Int,
    val spent: Float,
    val iconRes: Int
)

class RigorCategoryAdapter(
    private val onCategoryClick: (String) -> Unit
) : ListAdapter<RigorCategoryItem, RigorCategoryAdapter.ViewHolder>(DiffCallback()) {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val txtName: TextView = view.findViewById(R.id.categoryName)
        val spentBar: View = view.findViewById(R.id.spentBar)
        val progressOuter: View = view.findViewById(R.id.progressOuter)
        val txtSpent: TextView = view.findViewById(R.id.txtSpent)
        val txtLimit: TextView = view.findViewById(R.id.txtLimit)
        val iconView: ImageView = view.findViewById(R.id.categoryIcon)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_rigor_category, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = getItem(position)
        holder.txtName.text = item.name
        holder.iconView.setImageResource(item.iconRes)
        holder.txtSpent.text = "Spent: \u20B9${item.spent.toInt()}"
        holder.txtLimit.text = if (item.limit > 0) "Limit: \u20B9${item.limit}" else "Limit: \u2014"

        val progress = if (item.limit > 0) (item.spent / item.limit).coerceIn(0f, 1f) else 0f

        // Reset bar before animation to avoid recycled width
        holder.spentBar.layoutParams.width = 0
        holder.spentBar.requestLayout()
        if (item.limit > 0 && item.spent >= item.limit) {
            holder.spentBar.setBackgroundResource(R.drawable.bg_glass_progress_fill_red)
        } else {
            holder.spentBar.setBackgroundResource(R.drawable.bg_glass_progress_fill)
        }

        holder.progressOuter.post {
            val maxWidth = holder.progressOuter.width
            if (maxWidth <= 0) return@post
            val targetWidth = (maxWidth * progress).toInt()
            val anim = android.animation.ValueAnimator.ofInt(0, targetWidth)
            anim.addUpdateListener { va ->
                val v = va.animatedValue as Int
                holder.spentBar.layoutParams.width = v
                holder.spentBar.requestLayout()
            }
            anim.duration = 500
            anim.start()
        }

        holder.itemView.setOnClickListener { onCategoryClick(item.name) }
    }

    class DiffCallback : DiffUtil.ItemCallback<RigorCategoryItem>() {
        override fun areItemsTheSame(oldItem: RigorCategoryItem, newItem: RigorCategoryItem): Boolean {
            return oldItem.name == newItem.name
        }
        override fun areContentsTheSame(oldItem: RigorCategoryItem, newItem: RigorCategoryItem): Boolean {
            return oldItem == newItem
        }
    }
}
