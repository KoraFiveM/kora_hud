import { CashBank } from "@/components/hud/CashBank"
import { HealthArmour } from "@/components/hud/HealthArmour"
import { HungerThirst } from "@/components/hud/HungerThirst"
import { JobGang } from "@/components/hud/JobGang"
import { GaugesPreview, StatusPreview, VehiclePreview } from "@/components/hud/LayoutPreviews"
import { HUD_SECTIONS, LayoutEditorOverlay, MovableSection } from "@/components/hud/LayoutEditor"
import { MicIndicator } from "@/components/hud/MicIndicator"
import { Stamina } from "@/components/hud/Stamina"
import { StatusEffects } from "@/components/hud/StatusEffects"
import { Stress } from "@/components/hud/Stress"
import { VehicleInfo } from "@/components/hud/VehicleInfo"
import { HudStateProvider, useHudLayout, useHudVisible } from "@/lib/hudState"

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
 * The glanceable gauges and vehicle telemetry have independent bottom-centre
 * sections. The vehicle panel sits below the status gauges by default, but
 * can be positioned and scaled separately in the layout editor.
 *
 * Those four clusters are exactly the four movable sections: each one is
 * wrapped in a MovableSection carrying its own persisted id, and the position
 * classes below stay that section's zero point (see MovableSection's own
 * comment), so a player with nothing saved sees this layout unchanged.
 */
function HudContent() {
    const visible = useHudVisible()
    const layout = useHudLayout()
    if (!visible) return null

    return (
        <div className="pointer-events-none fixed inset-0 z-hud">
            <LayoutEditorOverlay />
            <MovableSection
                id={HUD_SECTIONS.gauges}
                label="Gauges"
                position="bottom-20 left-1/2"
                handlePosition="bottom-full left-1/2 mb-3 -translate-x-1/2"
                inner="gap-2"
                centerX
                scaleOrigin="center bottom"
            >
                {layout.editing ? (
                    <GaugesPreview />
                ) : (
                    <div className="flex items-center gap-2">
                        <HealthArmour />
                        <Stamina />
                        <HungerThirst />
                        <Stress />
                    </div>
                )}
            </MovableSection>
            <MovableSection
                id={HUD_SECTIONS.vehicle}
                label="Vehicle"
                position="bottom-4 left-1/2"
                handlePosition="bottom-full left-1/2 mb-3 -translate-x-1/2"
                centerX
                scaleOrigin="center bottom"
            >
                {layout.editing ? <VehiclePreview /> : <VehicleInfo />}
            </MovableSection>
            <MovableSection
                id={HUD_SECTIONS.identity}
                label="Player"
                position="bottom-4 right-4"
                handlePosition="bottom-full right-0 mb-3"
                inner="gap-2"
                scaleOrigin="right bottom"
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
                inner="gap-1.5"
                scaleOrigin="right top"
            >
                {layout.editing ? <StatusPreview /> : <StatusEffects />}
            </MovableSection>
            {/* qbchat owns the live composer in a separate NUI frame. This
                preview is only mounted while editing, but writes the shared
                offset that qbchat applies after Confirm. */}
            <MovableSection
                id={HUD_SECTIONS.chatInput}
                label="Chat input"
                position="left-4 top-4"
                handlePosition="top-full left-0 mt-3"
                scaleOrigin="left top"
                editorOnly
            >
                <div className="h-10 w-[min(480px,38vw)] rounded-[10px] border border-input bg-background/95 px-3 text-sm leading-10 text-muted-foreground">
                    Type a message or /command
                </div>
            </MovableSection>
        </div>
    )
}

/** Headless root; qbtheme's shared loader remains mounted outside React. */
export default function App() {
    return (
        <HudStateProvider>
            <HudContent />
        </HudStateProvider>
    )
}
