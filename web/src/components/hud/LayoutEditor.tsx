import { useRef, useState, type ReactNode } from "react"
import { Move } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudLayout } from "@/lib/hudState"
import type { HudLayoutOffset } from "@/lib/types"

/**
 * Section ids. PERSISTED -- these strings are the keys of the JSON blob in the
 * player's KVP (see client/hud.lua's readLayout), so renaming one silently
 * orphans every layout already saved under the old name. Add ids; don't
 * rename them.
 */
export const HUD_SECTIONS = {
    /** Bottom-centre: vehicle telemetry stacked over the glanceable gauge row. */
    gauges: "gauges",
    /** Bottom-right: mic, job/gang, money. */
    identity: "identity",
    /** Top-right: active qblib status effects. */
    status: "status",
} as const

// Matches client/hud.lua's LAYOUT_LIMIT exactly. Clamped here as well as there
// because the two clamps do different jobs: Lua's protects what gets stored,
// this one stops the section leaving the cursor behind mid-drag (the pointer
// keeps moving whether or not the offset still can).
const LAYOUT_LIMIT = 0.45

const ZERO: HudLayoutOffset = { x: 0, y: 0 }

function clamp(value: number): number {
    if (value > LAYOUT_LIMIT) return LAYOUT_LIMIT
    if (value < -LAYOUT_LIMIT) return -LAYOUT_LIMIT
    return value
}

/**
 * Offsets are viewport FRACTIONS, so they translate in vw/vh -- a percentage
 * would resolve against the section's own width instead, making the same
 * saved layout land somewhere different for a two-row money panel than for a
 * one-row one.
 *
 * `centerX` folds the bottom-centre cluster's own -50% shift into the same
 * transform rather than leaving it on an inner element. That keeps the
 * wrapper's box on top of what the player actually sees, which is what the
 * editor's outline and label are positioned against.
 */
function sectionTransform(offset: HudLayoutOffset, centerX: boolean): string {
    const x = `${offset.x * 100}vw`
    return `translate(${centerX ? `calc(-50% + ${x})` : x}, ${offset.y * 100}vh)`
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
    /** Layout classes for the section's own contents. */
    inner?: string
    /** True for the bottom-centre cluster; see sectionTransform. */
    centerX?: boolean
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
    inner,
    centerX = false,
    children,
}: MovableSectionProps) {
    const layout = useHudLayout()
    const nodeRef = useRef<HTMLDivElement>(null)
    const [dragging, setDragging] = useState(false)

    const offset = layout.offsets[id] ?? ZERO
    const draggable = layout.editing && layout.movable

    function handleMouseDown(event: React.MouseEvent<HTMLDivElement>) {
        if (!draggable) return
        const node = nodeRef.current
        if (!node) return
        // Otherwise the mousedown starts a text selection and the whole drag
        // reads as highlighting the HUD's labels.
        event.preventDefault()

        const startX = event.clientX
        const startY = event.clientY
        const base = offset
        let latest = base

        // Arrow consts, not function declarations: a hoisted declaration is
        // callable before the `node` null-check above, so TypeScript will not
        // carry that check into it.
        const onMove = (moveEvent: MouseEvent) => {
            latest = {
                x: clamp(base.x + (moveEvent.clientX - startX) / window.innerWidth),
                y: clamp(base.y + (moveEvent.clientY - startY) / window.innerHeight),
            }
            // Written straight to the node instead of through state: a drag
            // fires a mousemove per frame, and routing each one through React
            // would re-render this section (and re-run every gauge inside it)
            // at the cursor's rate for a change that is one CSS property.
            // State catches up once, on mouseup.
            node.style.transform = sectionTransform(latest, centerX)
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

    return (
        <div
            ref={nodeRef}
            // pointer-events-auto ONLY while the editor is open. The HUD is a
            // click-through overlay over live gameplay the rest of the time
            // (see globals.css) and has to stay that way -- a permanently
            // grabbable HUD would eat the clicks the game needs.
            className={cn("fixed", position, draggable && "pointer-events-auto", dragging ? "cursor-grabbing" : draggable && "cursor-grab")}
            style={{ transform: sectionTransform(offset, centerX) }}
            onMouseDown={handleMouseDown}
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
                            "hud-panel absolute flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-medium uppercase tracking-wide overlay-text",
                            handlePosition,
                        )}
                    >
                        <Move className="h-3 w-3 text-primary" aria-hidden />
                        {label}
                    </div>
                    <div className="pointer-events-none absolute -inset-2 rounded-2xl border border-dashed border-[hsl(var(--primary)/55%)]" />
                </>
            )}
            <div className={inner}>{children}</div>
        </div>
    )
}

/**
 * The editor's backdrop and hint. Rendered only while the editor is open, and
 * pointer-transparent throughout: Lua already took NUI focus for this mode, so
 * nothing here needs to catch a click, and a full-screen click target would
 * swallow the mousedown that starts a drag near a section's edge.
 */
export function LayoutEditorOverlay() {
    const layout = useHudLayout()
    if (!layout.editing) return null

    return (
        <div className="pointer-events-none fixed inset-0 bg-black/45">
            <div className="hud-panel absolute left-1/2 top-8 -translate-x-1/2 rounded-2xl px-5 py-3 text-center overlay-text">
                <p className="text-sm font-medium text-foreground">Drag any HUD section to move it</p>
                <p className="mt-1 text-xs text-muted-foreground">
                    <span className="font-mono text-foreground">/{layout.command}</span> to finish ·{" "}
                    <span className="font-mono text-foreground">/hudlayoutreset</span> to restore the defaults
                </p>
            </div>
        </div>
    )
}
