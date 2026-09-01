import { Briefcase, Users } from "lucide-react"

import { cn } from "@/lib/cn"
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
                {/* Duty status as a colour dot rather than text: green = on
                    duty, red = off duty. Always rendered so the panel width
                    doesn't jump on a duty toggle. */}
                <span
                    role="status"
                    aria-label={update.job.onDuty ? "on duty" : "off duty"}
                    title={update.job.onDuty ? "On duty" : "Off duty"}
                    className={cn(
                        "ml-auto h-2 w-2 shrink-0 rounded-full",
                        update.job.onDuty
                            ? "bg-success shadow-[0_0_6px_hsl(var(--success)/60%)]"
                            : "bg-destructive shadow-[0_0_6px_hsl(var(--destructive)/60%)]",
                    )}
                />
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
