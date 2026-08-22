import { Landmark, Wallet } from "lucide-react"

import { useHudState } from "@/lib/hudState"

function formatMoney(amount: number) {
    return `$${Math.round(amount).toLocaleString("en-US")}`
}

export function CashBank() {
    const { config, update } = useHudState()
    if (!config.elements.cash && !config.elements.bank) return null

    return (
        <div className="hud-chip flex flex-col gap-1 px-3 py-2 text-sm font-mono overlay-text">
            {config.elements.cash && (
                <div className="flex items-center gap-2 text-foreground">
                    <Wallet className="h-4 w-4 shrink-0 text-success" aria-hidden />
                    <span>{formatMoney(update.cash)}</span>
                </div>
            )}
            {config.elements.bank && (
                <div className="flex items-center gap-2 text-foreground">
                    <Landmark className="h-4 w-4 shrink-0 text-info" aria-hidden />
                    <span>{formatMoney(update.bank)}</span>
                </div>
            )}
        </div>
    )
}
