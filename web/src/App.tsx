import { HudThemeSynchronizer } from "@/components/theme/HudThemeSynchronizer"
import { CashBank } from "@/components/hud/CashBank"
import { HealthArmour } from "@/components/hud/HealthArmour"
import { HungerThirst } from "@/components/hud/HungerThirst"
import { JobGang } from "@/components/hud/JobGang"
import { MicIndicator } from "@/components/hud/MicIndicator"
import { Stamina } from "@/components/hud/Stamina"
import { StatusEffects } from "@/components/hud/StatusEffects"
import { Stress } from "@/components/hud/Stress"
import { VehicleInfo } from "@/components/hud/VehicleInfo"
import { HudStateProvider, useHudState } from "@/lib/hudState"

/**
 * The actual HUD layout, gated on login state. Each element is otherwise
 * self-contained -- it reads its own slice of HudStateProvider's context and
 * hides itself per Config.hud.elements -- so mounting all of them
 * unconditionally here (once visible) *is* the layout, same pattern as
 * qblib's own web/src/App.tsx. Split out from App so the visibility check has
 * HudStateProvider's context available (a provider's own children can't read
 * the context it provides).
 */
function HudContent() {
    const { visible } = useHudState()
    if (!visible) return null

    return (
        <div className="pointer-events-none fixed inset-0 z-hud flex flex-col justify-end p-4">
            <div className="flex items-end justify-between gap-4">
                <div className="flex flex-col gap-2">
                    <HealthArmour />
                    <Stamina />
                    <HungerThirst />
                    <Stress />
                </div>
                <div className="flex flex-col items-end gap-2">
                    <JobGang />
                    <CashBank />
                    <MicIndicator />
                </div>
            </div>
            <div className="mt-2 flex justify-center">
                <VehicleInfo />
            </div>
            <div className="pointer-events-none fixed right-4 top-4">
                <StatusEffects />
            </div>
        </div>
    )
}

/**
 * Headless root. HudThemeSynchronizer stays mounted regardless of visibility
 * (it renders nothing itself, just keeps CSS variables in sync) so the theme
 * is already correct the instant the HUD becomes visible.
 */
export default function App() {
    return (
        <HudStateProvider>
            <HudThemeSynchronizer />
            <HudContent />
        </HudStateProvider>
    )
}
