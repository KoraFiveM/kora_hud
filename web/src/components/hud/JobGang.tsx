import { Briefcase, Users } from "lucide-react"

import { useHudState } from "@/lib/hudState"

// Baseline "usual player data" -- always rendered, not config-toggleable.
export function JobGang() {
    const { update } = useHudState()

    return (
        <div className="hud-chip flex flex-col gap-1 px-3 py-2 text-sm overlay-text">
            <div className="flex items-center gap-2 text-foreground">
                <Briefcase className="h-4 w-4 shrink-0" aria-hidden />
                <span>
                    {update.job.label}
                    {update.job.onDuty ? " (on duty)" : ""}
                </span>
            </div>
            {update.gang && (
                <div className="flex items-center gap-2 text-muted-foreground">
                    <Users className="h-4 w-4 shrink-0" aria-hidden />
                    <span>{update.gang.label}</span>
                </div>
            )}
        </div>
    )
}
