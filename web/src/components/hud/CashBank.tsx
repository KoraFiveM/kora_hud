import { Landmark, Wallet } from "lucide-react"

import { useHudConfig, useHudUpdate } from "@/lib/hudState"

function formatMoney(amount: number) {
    return `$${Math.round(amount).toLocaleString("en-US")}`
}

export function CashBank() {
    const config = useHudConfig()
    const update = useHudUpdate()
    if (!config.elements.cash && !config.elements.bank) return null

    return (
        <div className="hud-panel flex flex-col gap-1.5 rounded-2xl px-3.5 py-2.5 text-sm font-mono overlay-text">
            {config.elements.cash && (
                <div className="flex items-center gap-2.5 text-foreground">
                    <span className="icon-badge icon-badge-success">
                        <Wallet className="h-3.5 w-3.5" aria-hidden />
                    </span>
                    <span>{formatMoney(update.cash)}</span>
                </div>
            )}
            {config.elements.bank && (
                <div className="flex items-center gap-2.5 text-foreground">
                    <span className="icon-badge icon-badge-info">
                        <Landmark className="h-3.5 w-3.5" aria-hidden />
                    </span>
                    <span>{formatMoney(update.bank)}</span>
                </div>
            )}
        </div>
    )
}
