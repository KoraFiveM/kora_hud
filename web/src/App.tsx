import { HudThemeSynchronizer } from "@/components/theme/HudThemeSynchronizer"
import { CashBank } from "@/components/hud/CashBank"
import { HealthArmour } from "@/components/hud/HealthArmour"
import { HungerThirst } from "@/components/hud/HungerThirst"
import { JobGang } from "@/components/hud/JobGang"
import { HUD_SECTIONS, LayoutEditorOverlay, MovableSection } from "@/components/hud/LayoutEditor"
import { MicIndicator } from "@/components/hud/MicIndicator"
import { Stamina } from "@/components/hud/Stamina"
import { StatusEffects } from "@/components/hud/StatusEffects"
import { Stress } from "@/components/hud/Stress"
import { VehicleInfo } from "@/components/hud/VehicleInfo"
import { HudStateProvider, useHudVisible } from "@/lib/hudState"

/**
 * The actual HUD layout, gated on login state. Each element is otherwise
 * self-contained -- it reads its own slice of HudStateProvider's contexts and
 * applies its configured element/dynamic visibility -- so mounting all of
 * them unconditionally here (once visible) *is* the layout, same pattern as
 * qblib's own web/src/App.tsx. Split out from App so the visibility check has
 * HudStateProvider's context available (a provider's own children can't read
 * the context it provides).
 *
 * Subscribes to visibility ONLY, deliberately. A parent re-render re-renders
 * its whole subtree regardless of memoisation, so reading the fast vitals
 * channel here would undo the point of splitting the contexts at all -- every
 * stamina tick would re-render the entire HUD from this node down. Visibility
 * changes a handful of times per session.
 *
 * The glanceable gauges live in a single bottom-centred row. Vehicle telemetry
 * stacks immediately above them when present, while the wider identity/money
 * panels remain independently pinned to the lower-right so neither can pull
 * the gauges away from the true screen centre.
 *
 * Those three clusters are exactly the three movable sections: each one is
 * wrapped in a MovableSection carrying its own persisted id, and the position
 * classes below stay that section's zero point (see MovableSection's own
 * comment), so a player with nothing saved sees this layout unchanged.
 */
function HudContent() {
    const visible = useHudVisible()
    if (!visible) return null

    return (
        <div className="pointer-events-none fixed inset-0 z-hud">
            <LayoutEditorOverlay />
            <MovableSection
                id={HUD_SECTIONS.gauges}
                label="Gauges"
                position="bottom-4 left-1/2"
                handlePosition="bottom-full left-1/2 mb-3 -translate-x-1/2"
                inner="flex flex-col items-center gap-2"
                centerX
            >
                <VehicleInfo />
                <div className="flex items-center gap-2">
                    <HealthArmour />
                    <Stamina />
                    <HungerThirst />
                    <Stress />
                </div>
            </MovableSection>
            <MovableSection
                id={HUD_SECTIONS.identity}
                label="Player"
                position="bottom-4 right-4"
                handlePosition="bottom-full right-0 mb-3"
                inner="flex flex-col items-end gap-2"
            >
                <MicIndicator />
                <JobGang />
                <CashBank />
            </MovableSection>
            {/* Handle BELOW this one: the section is pinned to the top of the
                screen, so a handle above it would render off the top edge. */}
            <MovableSection
                id={HUD_SECTIONS.status}
                label="Status"
                position="right-4 top-4"
                handlePosition="top-full right-0 mt-3"
            >
                <StatusEffects />
            </MovableSection>
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
