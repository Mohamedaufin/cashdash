package com.cash.dash

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

data class TransactionItem(val title: String, val category: String, val amount: Int, val rawEntry: String)

class TransactionAdapter(
    private val items: List<TransactionItem>,
    private val onItemLongClick: ((TransactionItem) -> Unit)? = null
) : RecyclerView.Adapter<TransactionAdapter.Holder>() {

    class Holder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.txtTransTitle)
        val category: TextView = view.findViewById(R.id.txtTransCategory)
        val amount: TextView = view.findViewById(R.id.txtTransAmount)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val v = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_transaction, parent, false)
        return Holder(v)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val item = items[position]
        holder.title.text = item.title
        holder.category.text = item.category
        holder.amount.text = "-₹${item.amount}"

        holder.itemView.setOnLongClickListener {
            onItemLongClick?.invoke(item)
            true
        }
    }

    override fun getItemCount() = items.size
}
