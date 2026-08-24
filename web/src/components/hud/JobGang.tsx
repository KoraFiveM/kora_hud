import { Briefcase, Users } from "lucide-react"

import { useHudState } from "@/lib/hudState"

// Baseline "usual player data" -- always rendered, not config-toggleable.
export function JobGang() {
    const { update } = useHudState()

    return (
        <div className="hud-panel flex flex-col gap-1.5 rounded-2xl px-3.5 py-2.5 text-sm overlay-text">
            <div className="flex items-center gap-2.5 text-foreground">
                <span className="icon-badge icon-badge-primary">
                    <Briefcase className="h-3.5 w-3.5" aria-hidden />
                </span>
                <span className="font-medium">{update.job.label}</span>
                {update.job.onDuty && <span className="text-[10px] font-semibold uppercase tracking-wide text-success">on duty</span>}
            </div>
            {update.gang && (
                <div className="flex items-center gap-2.5 text-muted-foreground">
                    <span className="icon-badge icon-badge-muted">
                        <Users className="h-3.5 w-3.5" aria-hidden />
                    </span>
                    <span>{update.gang.label}</span>
                </div>
            )}
        </div>
    )
}
