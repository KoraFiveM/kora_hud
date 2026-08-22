import { HudThemeSynchronizer } from "@/components/theme/HudThemeSynchronizer"
import { CashBank } from "@/components/hud/CashBank"
import { HealthArmour } from "@/components/hud/HealthArmour"
import { HungerThirst } from "@/components/hud/HungerThirst"
import { JobGang } from "@/components/hud/JobGang"
import { MicIndicator } from "@/components/hud/MicIndicator"
import { Stamina } from "@/components/hud/Stamina"
import { Stress } from "@/components/hud/Stress"
import { VehicleInfo } from "@/components/hud/VehicleInfo"
import { HudStateProvider } from "@/lib/hudState"

/**
 * Headless root every HUD element mounts under. Each element is
 * self-contained -- it reads its own slice of HudStateProvider's context and
 * hides itself per Config.hud.elements -- so mounting all of them
 * unconditionally here *is* the layout, same pattern as qblib's own
 * web/src/App.tsx.
 */
export default function App() {
    return (
        <HudStateProvider>
            <HudThemeSynchronizer />
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
            </div>
        </HudStateProvider>
    )
}
