import { useEffect, useState } from "react"
import { Landmark, Wallet } from "lucide-react"

import { useHudConfig, useHudUpdate } from "@/lib/hudState"

function formatMoney(amount: number) {
    return `$${Math.round(amount).toLocaleString("en-US")}`
}

function CashRow({ amount }: { amount: number }) {
    return (
        <div className="flex items-center gap-2.5 text-foreground">
            <span className="icon-badge icon-badge-success">
                <Wallet className="h-3.5 w-3.5" aria-hidden />
            </span>
            <span>{formatMoney(amount)}</span>
        </div>
    )
}

function BankRow({ amount }: { amount: number }) {
    return (
        <div className="flex items-center gap-2.5 text-foreground">
            <span className="icon-badge icon-badge-info">
                <Landmark className="h-3.5 w-3.5" aria-hidden />
            </span>
            <span>{formatMoney(amount)}</span>
        </div>
    )
}

export function CashBank() {
    const config = useHudConfig()
    const update = useHudUpdate()

    const showCash = config.elements.cash
    const showBank = config.elements.bank

    // Only alternate when there is genuinely something to alternate BETWEEN:
    // with one of the two elements switched off, "one account at a time" is
    // already what the panel shows, and cycling would blank it for half the
    // time instead.
    const cycling = config.money?.scrollAccounts === true && showCash && showBank
    const period = config.money?.scrollAccountsTime ?? 5000

    const [onBank, setOnBank] = useState(false)

    useEffect(() => {
        // No timer at all in the default (side-by-side) mode -- this is a HUD
        // component that stays mounted for the whole session, so an interval
        // that exists only to flip a flag nothing reads would be a permanent
        // wakeup for every player on the server.
        if (!cycling) return

        const timer = window.setInterval(() => setOnBank((current) => !current), Math.max(250, period))
        return () => window.clearInterval(timer)
    }, [cycling, period])

    if (!showCash && !showBank) return null

    return (
        <div className="hud-panel flex flex-col gap-1.5 rounded-2xl px-3.5 py-2.5 text-sm font-mono overlay-text">
            {cycling ? (
                // Keyed on which account is showing so React remounts the row
                // on every swap, which is what restarts the entry animation --
                // a plain conditional would swap the text in place and read as
                // a flicker rather than as a deliberate change.
                <div key={onBank ? "bank" : "cash"} className="money-swap">
                    {onBank ? <BankRow amount={update.bank} /> : <CashRow amount={update.cash} />}
                </div>
            ) : (
                <>
                    {showCash && <CashRow amount={update.cash} />}
                    {showBank && <BankRow amount={update.bank} />}
                </>
            )}
        </div>
    )
}
