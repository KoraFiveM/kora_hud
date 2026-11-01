import { useEffect, useRef, useState, type ReactNode } from "react"
import { AlignCenter, AlignLeft, AlignRight, Anchor, Check, Map as MapIcon, Maximize2, Move, RotateCcw, X } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudLayout } from "@/lib/hudState"
import type { HudLayoutJustification, HudLayoutOffset } from "@/lib/types"

/**
 * Section ids. PERSISTED -- these strings are the keys of the JSON blob in the
 * player's KVP (see client/hud.lua's readLayout), so renaming one silently
 * orphans every layout already saved under the old name. Add ids; don't
 * rename them.
 */
export const HUD_SECTIONS = {
    /** Bottom-centre: glanceable health/needs/status gauges. */
    gauges: "gauges",
    /** Bottom-centre, below the gauges: vehicle telemetry while driving. */
    vehicle: "vehicle",
    /** Bottom-right: mic, job/gang, money. */
    identity: "identity",
    /** Top-right: active kora_lib status effects. */
    status: "status",
    /** qbchat's composer, stored by qbhud but rendered in qbchat's NUI. */
    chatInput: "chatInput",
} as const

// Matches client/hud.lua's section-aware LAYOUT_BOUNDS exactly. The default
// anchors differ (bottom-centre, bottom-right and top-right), so their travel
// ranges differ too: using one +/- limit strands every corner section on only
// half of the screen.
const SECTION_BOUNDS: Record<string, { minX: number; maxX: number; minY: number; maxY: number }> = {
    [HUD_SECTIONS.gauges]: { minX: -0.5, maxX: 0.5, minY: -0.95, maxY: 0 },
    [HUD_SECTIONS.vehicle]: { minX: -0.5, maxX: 0.5, minY: -0.95, maxY: 0 },
    [HUD_SECTIONS.identity]: { minX: -0.95, maxX: 0, minY: -0.95, maxY: 0 },
    [HUD_SECTIONS.status]: { minX: -0.95, maxX: 0, minY: 0, maxY: 0.95 },
    [HUD_SECTIONS.chatInput]: { minX: -0.95, maxX: 0.95, minY: -0.95, maxY: 0.95 },
}
const FALLBACK_LAYOUT_LIMIT = 0.45
const SCALE_MIN = 0.75
const SCALE_MAX = 1.5
const ANGLE_SNAP_RADIANS = Math.PI / 4
const GRID_SNAP_INCREMENT = 0.05

const DEFAULT_JUSTIFICATIONS: Record<string, HudLayoutJustification> = {
    [HUD_SECTIONS.gauges]: "center",
    [HUD_SECTIONS.vehicle]: "center",
    [HUD_SECTIONS.identity]: "right",
    [HUD_SECTIONS.status]: "right",
    [HUD_SECTIONS.chatInput]: "left",
}

const ZERO: HudLayoutOffset = { x: 0, y: 0 }

function clamp(section: string, axis: "x" | "y", value: number): number {
    const bounds = SECTION_BOUNDS[section]
    const minimum = bounds ? (axis === "x" ? bounds.minX : bounds.minY) : -FALLBACK_LAYOUT_LIMIT
    const maximum = bounds ? (axis === "x" ? bounds.maxX : bounds.maxY) : FALLBACK_LAYOUT_LIMIT
    if (value > maximum) return maximum
    if (value < minimum) return minimum
    return value
}

/**
 * main.tsx renders the HUD in a smaller coordinate space and scales it up on
 * displays above 1920×1080. Fixed children live in that coordinate space, so
 * layout translations must be converted back to its unscaled pixels.  Without
 * this conversion, a 50% drag on a 4K display becomes a 100% on-screen move
 * after the root is scaled, which makes the lower and far-edge positions
 * unreachable.
 */
function nuiScale(): number {
    return Math.min(2, Math.max(0.5, Math.min(window.innerWidth / 1920, window.innerHeight / 1080)))
}

function layoutViewport(): { width: number; height: number } {
    const scale = nuiScale()
    return { width: window.innerWidth / scale, height: window.innerHeight / scale }
}

function clampDelta(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value))
}

/**
 * Constrains a drag to one of the eight cardinal/diagonal directions. Keeping
 * this in pixels preserves the apparent angle on non-square viewports before
 * the offset is converted to independent x/y viewport fractions.
 */
function snapDragAngle(deltaX: number, deltaY: number): { x: number; y: number } {
    const distance = Math.hypot(deltaX, deltaY)
    if (distance === 0) return { x: 0, y: 0 }

    const angle = Math.atan2(deltaY, deltaX)
    const snappedAngle = Math.round(angle / ANGLE_SNAP_RADIANS) * ANGLE_SNAP_RADIANS
    return {
        x: Math.cos(snappedAngle) * distance,
        y: Math.sin(snappedAngle) * distance,
    }
}

/** Snaps a viewport-fraction offset to the layout editor's 5% grid. */
function snapOffsetToGrid(value: number): number {
    return Math.round(value / GRID_SNAP_INCREMENT) * GRID_SNAP_INCREMENT
}

/**
 * Offsets are viewport FRACTIONS. They are converted to pixels in the HUD's
 * own coordinate space rather than CSS percentages, which would resolve
 * against the section's own width and make the same saved layout land
 * differently for a two-row money panel than for a one-row one.
 *
 * Centre alignment folds the cluster's own -50% shift into the same
 * transform rather than leaving it on an inner element. That keeps the
 * wrapper's box on top of what the player actually sees, which is what the
 * editor's outline and label are positioned against.
 */
function sectionTransform(offset: HudLayoutOffset, centered: boolean): string {
    const viewport = layoutViewport()
    const x = `${offset.x * viewport.width}px`
    const y = `${offset.y * viewport.height}px`
    return `translate(${centered ? `calc(-50% + ${x})` : x}, ${y})`
}

function scaleTransform(offset: HudLayoutOffset, centered: boolean, scale: number): string {
    return `${sectionTransform(offset, centered)} scale(${scale})`
}

interface MovableSectionProps {
    /** A key of HUD_SECTIONS -- see the note there before changing one. */
    id: string
    /** Shown on the drag handle while the editor is open. */
    label: string
    /** Tailwind classes pinning this section's DEFAULT position (its zero point). */
    position: string
    /** Classes positioning the handle so it can't overlap the screen edge. */
    handlePosition: string
    /** Handle position once this section crosses to the opposite screen half. */
    flippedHandlePosition?: string
    /** Layout classes for the section's own contents. */
    inner?: string
    /** True for the bottom-centre cluster; see sectionTransform. */
    centerX?: boolean
    /** The fixed corner each section should grow from when resized. */
    scaleOrigin?: string
    /** A layout-editor proxy for a component rendered by another NUI. */
    editorOnly?: boolean
    /** Shows the gauges-only bottom-anchor toggle in the layout controls. */
    bottomAnchored?: boolean
    children: ReactNode
}

/**
 * Wraps one HUD cluster in its saved offset, and makes it draggable while the
 * layout editor is open.
 *
 * The offset is applied ON TOP OF the `position` classes rather than replacing
 * them, so each section's hardcoded corner stays its zero point: an empty
 * offsets map renders exactly the layout that shipped, and a player who
 * resets goes back to it rather than to the top-left of the screen.
 */
export function MovableSection({
    id,
    label,
    position,
    handlePosition,
    flippedHandlePosition,
    inner,
    centerX = false,
    scaleOrigin = "center",
    editorOnly = false,
    bottomAnchored,
    children,
}: MovableSectionProps) {
    const layout = useHudLayout()
    const nodeRef = useRef<HTMLDivElement>(null)
    const [dragging, setDragging] = useState(false)

    const offset = layout.offsets[id] ?? ZERO
    const scale = layout.scales[id] ?? 1
    const justification = layout.justifications[id] ?? DEFAULT_JUSTIFICATIONS[id] ?? "right"
    const AlignmentIcon = justification === "left" ? AlignLeft : justification === "center" ? AlignCenter : AlignRight
    const draggable = layout.editing && layout.movable
    const handleShouldFlip = (handlePosition.includes("top-full") && offset.y > 0.5)
        || (handlePosition.includes("bottom-full") && offset.y < -0.5)
    const activeHandlePosition = handleShouldFlip && flippedHandlePosition
        ? flippedHandlePosition
        : handlePosition

    function handleMoveMouseDown(event: React.MouseEvent<HTMLElement>) {
        if (!draggable) return
        const node = nodeRef.current
        if (!node) return
        // Otherwise the mousedown starts a text selection and the whole drag
        // reads as highlighting the HUD's labels.
        event.preventDefault()

        const startX = event.clientX
        const startY = event.clientY
        const base = offset
        const startRect = node.getBoundingClientRect()
        let latest = base

        // Arrow consts, not function declarations: a hoisted declaration is
        // callable before the `node` null-check above, so TypeScript will not
        // carry that check into it.
        const onMove = (moveEvent: MouseEvent) => {
            // Keep the visible section inside the real browser viewport. This
            // is deliberately measured from its rendered box rather than a
            // fixed fraction: status effects, money rows and scaled sections
            // all have different dimensions. It lets a status stack sit at
            // the bottom edge without letting its controls disappear beyond
            // it.
            let deltaX = clampDelta(
                moveEvent.clientX - startX,
                -startRect.left,
                window.innerWidth - startRect.right,
            )
            let deltaY = clampDelta(
                moveEvent.clientY - startY,
                -startRect.top,
                window.innerHeight - startRect.bottom,
            )
            if (moveEvent.shiftKey) {
                const snappedDelta = snapDragAngle(deltaX, deltaY)
                deltaX = snappedDelta.x
                deltaY = snappedDelta.y
            }
            const nextOffset = {
                x: clamp(id, "x", base.x + deltaX / window.innerWidth),
                y: clamp(id, "y", base.y + deltaY / window.innerHeight),
            }
            latest = moveEvent.ctrlKey
                ? {
                    x: clamp(id, "x", snapOffsetToGrid(nextOffset.x)),
                    y: clamp(id, "y", snapOffsetToGrid(nextOffset.y)),
                }
                : nextOffset
            // Written straight to the node instead of through state: a drag
            // fires a mousemove per frame, and routing each one through React
            // would re-render this section (and re-run every gauge inside it)
            // at the cursor's rate for a change that is one CSS property.
            // State catches up once, on mouseup.
            node.style.transform = scaleTransform(latest, centerX, scale)
        }

        const onUp = () => {
            window.removeEventListener("mousemove", onMove)
            window.removeEventListener("mouseup", onUp)
            setDragging(false)
            // Identity check, not a deep compare: `latest` is only ever
            // reassigned by onMove, so this is exactly "did the pointer
            // actually move" -- a click on a section with no drag behind it
            // should not spend a KVP write re-saving the layout unchanged.
            if (latest !== base) layout.commitOffset(id, latest)
        }

        // On `window`, not on the section: the cursor routinely outruns the
        // element it is dragging, and a listener on the element itself would
        // then stop tracking (and never see the mouseup) the moment it does.
        window.addEventListener("mousemove", onMove)
        window.addEventListener("mouseup", onUp)
        setDragging(true)
    }

    function handleResizeMouseDown(event: React.MouseEvent<HTMLButtonElement>) {
        if (!draggable) return
        // This is deliberately a pointer/mouse gesture, not an HTML5 drag
        // operation. Native dragging produces browser ghost previews and does
        // not reliably report its position inside FiveM's embedded browser.
        event.preventDefault()
        event.stopPropagation()

        const startX = event.clientX
        const base = scale
        let latest = base

        const onMove = (moveEvent: MouseEvent) => {
            // Horizontal movement is intentional: it makes every section
            // resize consistently regardless of which fixed corner it grows
            // from. A full viewport-width drag spans the complete 75–150%
            // range, while smaller adjustments remain easy to control.
            latest = clampDelta(base + (moveEvent.clientX - startX) / window.innerWidth, SCALE_MIN, SCALE_MAX)
            const node = nodeRef.current
            if (node) node.style.transform = scaleTransform(offset, centerX, latest)
        }

        const onUp = () => {
            window.removeEventListener("mousemove", onMove)
            window.removeEventListener("mouseup", onUp)
            if (latest !== base) layout.commitScale(id, latest)
        }

        window.addEventListener("mousemove", onMove)
        window.addEventListener("mouseup", onUp)
    }

    function cycleJustification() {
        layout.commitJustification(id, justification === "left" ? "center" : justification === "center" ? "right" : "left")
    }

    function toggleBottomAnchor() {
        layout.setGaugesBottomAnchored(!bottomAnchored)
    }

    // kora_hud draws a proxy for kora_chat's composer only while arranging the
    // layout; kora_chat continues to own the real input during normal play.
    if (editorOnly && !layout.editing) return null

    return (
        <div
            ref={nodeRef}
            // pointer-events-auto ONLY while the editor is open. The HUD is a
            // click-through overlay over live gameplay the rest of the time
            // (see globals.css) and has to stay that way -- only the explicit
            // control icons take pointer input while editing.
            className={cn("fixed transition-[bottom] duration-200 ease-out", position, draggable && "pointer-events-auto")}
            style={{
                transform: scaleTransform(offset, centerX, scale),
                transformOrigin: scaleOrigin,
            }}
        >
            {draggable && (
                <>
                    {/* Absolutely positioned, not in flow: opening the editor
                        must not move the very geometry the player is about to
                        line up. It doubles as the section's body when the
                        cluster itself renders nothing (status effects with no
                        effects active), which would otherwise leave a
                        zero-size section with nothing to grab. */}
                    <div
                        className={cn(
                            "hud-panel absolute flex items-center gap-1 rounded-full p-1 overlay-text",
                            activeHandlePosition,
                        )}
                    >
                        <button
                            type="button"
                            aria-label={`Move ${label}`}
                            title="Drag to move. Hold Ctrl to snap to the grid; hold Shift to snap to 45° angles"
                            onMouseDown={handleMoveMouseDown}
                            className={cn("flex h-7 w-7 items-center justify-center rounded-full text-primary", dragging ? "cursor-grabbing" : "cursor-grab")}
                        >
                            <Move className="h-3.5 w-3.5" aria-hidden />
                        </button>
                        {bottomAnchored !== undefined && (
                            <button
                                type="button"
                                aria-label={bottomAnchored ? "Gauges are anchored to the bottom. Click to use a fixed position." : "Gauges use a fixed position. Click to anchor them to the bottom."}
                                title={bottomAnchored ? "Bottom anchored: move above the vehicle HUD automatically" : "Fixed position: do not move for the vehicle HUD"}
                                onClick={toggleBottomAnchor}
                                className={cn("flex h-7 w-7 items-center justify-center rounded-full transition-colors", bottomAnchored ? "bg-primary text-primary-foreground" : "text-primary hover:bg-muted")}
                            >
                                <Anchor className="h-3.5 w-3.5" aria-hidden />
                            </button>
                        )}
                        <button
                            type="button"
                            aria-label={`Resize ${label}; drag left or right`}
                            title="Drag left or right to resize"
                            onMouseDown={handleResizeMouseDown}
                            className="flex h-7 w-7 cursor-ew-resize items-center justify-center rounded-full text-primary"
                        >
                            <Maximize2 className="h-3.5 w-3.5" aria-hidden />
                        </button>
                        {!editorOnly && (
                            <button
                                type="button"
                                aria-label={`Content alignment: ${justification}. Click to cycle alignment.`}
                                title="Cycle content alignment: Left, Centre, Right"
                                onClick={cycleJustification}
                                className="flex h-7 w-7 items-center justify-center rounded-full text-primary"
                            >
                                <AlignmentIcon className="h-3.5 w-3.5" aria-hidden />
                            </button>
                        )}
                    </div>
                    <div className="pointer-events-none absolute -inset-2 rounded-2xl border border-dashed border-[hsl(var(--primary)/55%)]" />
                </>
            )}
            <div className={cn("flex flex-col", inner, justification === "left" ? "items-start text-left" : justification === "center" ? "items-center text-center" : "items-end text-right")}>
                {children}
            </div>
        </div>
    )
}

/**
 * The editor backdrop and compact bottom-left actions. The backdrop remains
 * pointer-transparent so it cannot swallow a section-control drag.
 */
export function LayoutEditorOverlay() {
    const layout = useHudLayout()

    useEffect(() => {
        if (!layout.editing) return
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key === "Escape") layout.cancel()
        }
        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [layout.editing, layout.cancel])

    if (!layout.editing) return null

    return (
        <div className="pointer-events-none fixed inset-0 bg-black/45">
            <div className="absolute left-1/2 top-1/2 flex w-fit -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-2">
                <div className="hud-panel pointer-events-auto flex w-fit items-center gap-1 rounded-full p-1 overlay-text">
                    <button
                        type="button"
                        aria-label="Confirm layout changes"
                        title="Confirm"
                        onClick={layout.confirm}
                        className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-primary-foreground transition-opacity hover:opacity-90"
                    >
                        <Check className="h-4 w-4" aria-hidden />
                    </button>
                    <button
                        type="button"
                        aria-label="Close without saving layout changes"
                        title="Close without saving"
                        onClick={layout.cancel}
                        className="flex h-8 w-8 items-center justify-center rounded-full text-foreground transition-colors hover:bg-muted"
                    >
                        <X className="h-4 w-4" aria-hidden />
                    </button>
                    <button
                        type="button"
                        aria-label="Reset HUD layout to defaults"
                        title="Reset to defaults"
                        onClick={layout.resetToDefaults}
                        className="flex h-8 w-8 items-center justify-center rounded-full text-foreground transition-colors hover:bg-muted"
                    >
                        <RotateCcw className="h-4 w-4" aria-hidden />
                    </button>
                </div>
                {/* Per player, saved with the layout. Hidden when the server pins
                    it (Config.hud.minimapVehicleOnly.allowPlayerChange = false). */}
                {layout.minimapVehicleOnlyAllowed && (
                    <button
                        type="button"
                        role="switch"
                        aria-checked={layout.minimapVehicleOnly}
                        title="Show the minimap only while you are in a vehicle"
                        onClick={() => layout.setMinimapVehicleOnly(!layout.minimapVehicleOnly)}
                        className="hud-panel pointer-events-auto flex items-center gap-2 rounded-full px-3 py-1.5 text-sm text-foreground overlay-text transition-colors hover:bg-muted"
                    >
                        <MapIcon className="h-4 w-4 text-primary" aria-hidden />
                        <span>Minimap only in vehicle</span>
                        <span
                            aria-hidden
                            className={cn(
                                "flex h-5 w-9 items-center rounded-full p-0.5 transition-colors",
                                layout.minimapVehicleOnly ? "bg-primary" : "bg-border",
                            )}
                        >
                            <span
                                className={cn(
                                    "h-4 w-4 rounded-full bg-primary-foreground transition-transform",
                                    layout.minimapVehicleOnly ? "translate-x-4" : "translate-x-0",
                                )}
                            />
                        </span>
                    </button>
                )}
            </div>
        </div>
    )
}
