import { CashBank } from "@/components/hud/CashBank"
import { HealthArmour } from "@/components/hud/HealthArmour"
import { HungerThirst } from "@/components/hud/HungerThirst"
import { JobGang } from "@/components/hud/JobGang"
import { GaugesPreview, StatusPreview, VehiclePreview } from "@/components/hud/LayoutPreviews"
import { HUD_SECTIONS, LayoutEditorOverlay, MovableSection } from "@/components/hud/LayoutEditor"
import { MicIndicator } from "@/components/hud/MicIndicator"
import { EditorPanel, ExternalProxy } from "@/components/hud/UiEditor"
import { PlayerId } from "@/components/hud/PlayerId"
import { SeatbeltSound } from "@/components/SeatbeltSound"
import { Stamina } from "@/components/hud/Stamina"
import { StatusEffects } from "@/components/hud/StatusEffects"
import { Stress } from "@/components/hud/Stress"
import { VehicleInfo } from "@/components/hud/VehicleInfo"
import { HudStateProvider, useHudLayout, useHudVehicle, useHudVisible } from "@/lib/hudState"
import { memo } from "react"

/**
 * The actual HUD layout, gated on login state. Each element is otherwise
 * self-contained -- it reads its own slice of HudStateProvider's contexts and
 * applies its configured element/dynamic visibility -- so mounting all of
 * them unconditionally here (once visible) *is* the layout, same pattern as
 * kora_lib's own web/src/App.tsx. Split out from App so the visibility check has
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
 * sections. By default the standalone gauge row is bottom-anchored; when the
 * vehicle panel appears it takes the bottom slot and the gauges glide above
 * it. Players can turn this arrangement off from the gauges' editor controls.
 *
 * Those four clusters are exactly the four movable sections: each one is
 * wrapped in a MovableSection carrying its own persisted id, and the position
 * classes below stay that section's zero point (see MovableSection's own
 * comment), so a player with nothing saved sees this layout unchanged.
 */
const GaugesSection = memo(function GaugesSection({ position, bottomAnchored }: { position: string; bottomAnchored: boolean }) {
    const layout = useHudLayout()
    return (
        <MovableSection
            id={HUD_SECTIONS.gauges}
            label="Gauges"
            position={position}
            handlePosition="bottom-full left-1/2 mb-3 -translate-x-1/2"
            flippedHandlePosition="top-full left-1/2 mt-3 -translate-x-1/2"
            inner="gap-2"
            centerX
            scaleOrigin="center bottom"
            bottomAnchored={bottomAnchored}
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
    )
})

const VehicleSection = memo(function VehicleSection() {
    const layout = useHudLayout()
    return (
        <MovableSection
            id={HUD_SECTIONS.vehicle}
            label="Vehicle"
            position="bottom-4 left-1/2 max-[520px]:bottom-2"
            handlePosition="bottom-full left-1/2 mb-3 -translate-x-1/2"
            flippedHandlePosition="top-full left-1/2 mt-3 -translate-x-1/2"
            centerX
            scaleOrigin="center bottom"
        >
            {layout.editing ? <VehiclePreview /> : <VehicleInfo />}
        </MovableSection>
    )
})

function BottomHud() {
    const layout = useHudLayout()
    const vehicle = useHudVehicle()
    // Layout mode always shows the vehicle preview, so reserve its bottom
    // slot there too instead of letting the two editor previews overlap.
    const vehicleActive = vehicle !== null || layout.editing
    const gaugesPosition = layout.gaugesBottomAnchored
        ? vehicleActive ? "bottom-20 left-1/2 max-[520px]:bottom-16" : "bottom-4 left-1/2 max-[520px]:bottom-2"
        : "bottom-20 left-1/2 max-[520px]:bottom-16"

    return (
        <>
            <GaugesSection position={gaugesPosition} bottomAnchored={layout.gaugesBottomAnchored} />
            <VehicleSection />
        </>
    )
}

function HudContent() {
    const visible = useHudVisible()
    const layout = useHudLayout()
    if (!visible) return null

    return (
        <div className="pointer-events-none fixed inset-0 z-hud">
            {/* The unified /ui panel, or the classic compact editor when
                Config.uiEditor is off (or client/hud.lua is older). */}
            {layout.editor.enabled ? <EditorPanel /> : <LayoutEditorOverlay />}
            {/* Outline proxies for elements other resources (and the game, for
                the minimap) render. Only while editing. */}
            {layout.editing && layout.editor.enabled && layout.elements.map((element) => (
                <ExternalProxy key={element.id} def={element} />
            ))}
            <BottomHud />
            <MovableSection
                id={HUD_SECTIONS.identity}
                label="Player"
                position="bottom-4 right-4 max-[520px]:bottom-2 max-[520px]:right-2"
                handlePosition="bottom-full right-0 mb-3"
                flippedHandlePosition="top-full right-0 mt-3"
                inner="gap-2"
                scaleOrigin="right bottom"
            >
                <MicIndicator />
                <JobGang />
                <CashBank />
                <PlayerId />
            </MovableSection>
            {/* The editor moves this handle to the inward-facing side after
                the section crosses the screen, so it always remains usable. */}
            <MovableSection
                id={HUD_SECTIONS.status}
                label="Status"
                position="right-4 top-4 max-[520px]:right-2 max-[520px]:top-2"
                handlePosition="top-full right-0 mt-3"
                flippedHandlePosition="bottom-full right-0 mb-3"
                inner="gap-1.5"
                scaleOrigin="right top"
            >
                {layout.editing ? <StatusPreview /> : <StatusEffects />}
            </MovableSection>
            {/* qbchat owns the live composer in a separate NUI frame. This
                preview is only mounted while editing, but writes the shared
                position and scale that qbchat applies after Confirm. A
                kora_chat that registers with the /ui editor gets a generic
                proxy instead, so this one is only for an older kora_chat. */}
            {!layout.elements.some((element) => element.id === HUD_SECTIONS.chatInput) && <MovableSection
                id={HUD_SECTIONS.chatInput}
                label="Chat input"
                position="left-4 top-4 max-[520px]:left-2 max-[520px]:top-2"
                handlePosition="top-full left-0 mt-3"
                flippedHandlePosition="bottom-full left-0 mb-3"
                scaleOrigin="left top"
                editorOnly
            >
                <div className="h-12 w-[min(480px,38vw)] max-[520px]:w-[calc(100vw-1rem)] rounded-[10px] bg-background/95 px-3 text-sm leading-[3rem] text-muted-foreground">
                    Type a message or /command
                </div>
            </MovableSection>}
        </div>
    )
}

/** Headless root; qbtheme's shared loader remains mounted outside React. */
export default function App() {
    return (
        <HudStateProvider>
            <SeatbeltSound />
            <HudContent />
        </HudStateProvider>
    )
}
