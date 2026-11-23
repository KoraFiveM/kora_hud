import type { LucideIcon } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudConfig, useHudLayout } from "@/lib/hudState"
import type { HudGaugeShape } from "@/lib/types"

/**
 * Every shape a player can pick in /ui > Gauges > Shape. Must match
 * GAUGE_SHAPES in client/hud.lua, which validates the saved choice.
 */
export const GAUGE_SHAPES: HudGaugeShape[] = ["circle", "square", "hexagon", "triangle", "diamond", "bar"]

function isGaugeShape(value: unknown): value is HudGaugeShape {
    return typeof value === "string" && (GAUGE_SHAPES as string[]).includes(value)
}

/** This player's gauge shape: their own /ui choice, else Config.hud.gaugeShape. */
export function useGaugeShape(): HudGaugeShape {
    const config = useHudConfig()
    const layout = useHudLayout()
    const chosen = layout.settings.gauges?.shape
    if (isGaugeShape(chosen)) return chosen
    return isGaugeShape(config.gaugeShape) ? config.gaugeShape : "circle"
}

interface RadialGaugeProps {
    icon: LucideIcon
    value: number
    label: string
    color: string
    size?: number
    stroke?: number
    /** The neutral value hidden when Config.hud.dynamic is enabled. */
    defaultValue: number
    /**
     * Pulses the gauge once it's colored destructive. Keyed off `color`
     * rather than a raw value threshold since "critical" is direction-
     * dependent -- a low value for health, but a high one for stress (see
     * statColor's `invert`) -- and `color` already resolved that via
     * whatever banding the caller used.
     */
    pulse?: boolean
    /** Overrides the player's shape (layout previews of a specific shape). */
    shape?: HudGaugeShape
}

// Padding between the meter and its own panel -- same on every gauge
// regardless of `size` so a row of differently-sized gauges (e.g. the 44px
// vitals next to the 36px vehicle fuel gauge) still reads as one consistent
// badge shape rather than mismatched meter-to-panel ratios.
const PANEL_PADDING = 4

type Point = [number, number]

interface ShapeGeometry {
    width: number
    height: number
    /** Panel outline, then the meter's track/progress path inset by `inset`. */
    path: (inset: number) => string
    /** Where the icon sits (the shape's visual centre). */
    iconCenter: Point
}

const fmt = (n: number) => Math.round(n * 100) / 100

/**
 * A closed path around a regular polygon that STARTS at its topmost point
 * (a vertex, or the middle of a flat top edge) and runs clockwise, so a
 * dash-offset fill grows from 12 o'clock exactly like the circular ring.
 */
function polygonPath(center: Point, circumradius: number, sides: number, rotationDeg: number): string {
    const [cx, cy] = center
    const vertices: { angle: number; point: Point }[] = []
    for (let index = 0; index < sides; index++) {
        // Normalised to (-90, 270] so "clockwise from the top" is ascending.
        let angle = rotationDeg + (index * 360) / sides
        while (angle <= -90 - 1e-6) angle += 360
        while (angle > 270 - 1e-6) angle -= 360
        const radians = (angle * Math.PI) / 180
        vertices.push({ angle, point: [cx + circumradius * Math.cos(radians), cy + circumradius * Math.sin(radians)] })
    }
    vertices.sort((a, b) => a.angle - b.angle)
    const topIsVertex = Math.abs(vertices[0].angle + 90) < 1e-3
    const last = vertices[vertices.length - 1].point
    const first = vertices[0].point
    const start: Point = topIsVertex ? first : [(last[0] + first[0]) / 2, (last[1] + first[1]) / 2]
    const rest = topIsVertex ? vertices.slice(1) : vertices
    return `M${fmt(start[0])} ${fmt(start[1])} ${rest.map(({ point }) => `L${fmt(point[0])} ${fmt(point[1])}`).join(" ")} Z`
}

/** Rounded square, starting top-centre and running clockwise. */
function roundedSquarePath(size: number, inset: number, radius: number): string {
    const min = inset
    const max = size - inset
    const r = Math.max(0, radius - inset)
    const c = size / 2
    return [
        `M${fmt(c)} ${fmt(min)}`,
        `H${fmt(max - r)}`,
        `A${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(max)} ${fmt(min + r)}`,
        `V${fmt(max - r)}`,
        `A${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(max - r)} ${fmt(max)}`,
        `H${fmt(min + r)}`,
        `A${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(min)} ${fmt(max - r)}`,
        `V${fmt(min + r)}`,
        `A${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(min + r)} ${fmt(min)}`,
        "Z",
    ].join(" ")
}

/**
 * Geometry for each outline shape at a given panel size. Insetting a regular
 * n-gon's edges by `d` shrinks its circumradius by d / cos(pi / n), which is
 * what keeps the track an even distance inside the panel edge on every side.
 */
function shapeGeometry(shape: Exclude<HudGaugeShape, "circle" | "bar">, panel: number): ShapeGeometry {
    const c = panel / 2
    switch (shape) {
        case "square": {
            const radius = panel * 0.22
            return { width: panel, height: panel, path: (inset) => roundedSquarePath(panel, inset, radius), iconCenter: [c, c] }
        }
        case "diamond": {
            const shrink = Math.SQRT2
            return { width: panel, height: panel, path: (inset) => polygonPath([c, c], c - inset * shrink, 4, -90), iconCenter: [c, c] }
        }
        case "hexagon": {
            const shrink = 1 / Math.cos(Math.PI / 6)
            const width = panel * Math.cos(Math.PI / 6)
            return {
                width,
                height: panel,
                path: (inset) => polygonPath([width / 2, c], c - inset * shrink, 6, -90),
                iconCenter: [width / 2, c],
            }
        }
        case "triangle": {
            // An equilateral triangle needs a wider box than the other shapes
            // for its inscribed circle to hold the icon. Its centroid sits a
            // quarter of the circumradius below the box centre.
            const width = panel * 1.3
            const circumradius = width / Math.sqrt(3)
            const height = circumradius * 1.5
            const centroid: Point = [width / 2, circumradius]
            return { width, height, path: (inset) => polygonPath(centroid, circumradius - inset * 2, 3, -90), iconCenter: centroid }
        }
    }
}

/**
 * Shared glanceable meter every vital (health/armour/stamina/hunger/thirst/
 * stress/fuel) renders through, so they look and behave identically. `value`
 * is clamped to 0-100 -- callers convert whatever native range their stat
 * uses (e.g. health's 100-200) before passing it in. Each gauge is its own
 * hud-panel badge -- not grouped inside a shared rectangle -- so a row of them
 * reads as separate glanceable dials. The shape (ring, polygon outline or a
 * horizontal bar) is the player's /ui choice; see useGaugeShape. In dynamic
 * mode, each caller's declared `defaultValue` is also the gauge's hidden state.
 */
export function RadialGauge({
    icon: Icon,
    value,
    label,
    color,
    defaultValue,
    size = 44,
    stroke = 3.5,
    pulse = false,
    shape: shapeOverride,
}: RadialGaugeProps) {
    const config = useHudConfig()
    const playerShape = useGaugeShape()
    const shape = shapeOverride ?? playerShape
    const clamped = Math.max(0, Math.min(100, value))
    // Animate over exactly one update interval so the meter interpolates from
    // one sample to the next instead of jumping and then sitting still. This
    // is what decouples "smooth" from "frequent": Lua can send vitals every
    // 150ms (or 250, or 400) and the meter still sweeps continuously, because
    // the browser -- which is already compositing this frame -- fills in
    // between samples instead of Lua paying to produce more of them.
    const sweep = `${config.vitalsInterval}ms`
    const clampedDefault = Math.max(0, Math.min(100, defaultValue))

    // Compare the clamped values so engine noise outside the documented
    // 0-100 range (e.g. 100.0001 fuel) still counts as the neutral boundary.
    if (config.dynamic && clamped === clampedDefault) return null

    const panelSize = size + PANEL_PADDING * 2
    const critical = pulse && color === "hsl(var(--destructive))"
    const meter = {
        role: "meter" as const,
        "aria-label": label,
        "aria-valuemin": 0,
        "aria-valuemax": 100,
        "aria-valuenow": Math.round(clamped),
        title: `${label}: ${Math.round(clamped)}%`,
    }

    if (shape === "bar") {
        return (
            <div
                className={cn("hud-panel flex shrink-0 items-center gap-2 rounded-full pl-2.5 pr-3", critical && "animate-pulse")}
                style={{ height: panelSize }}
                {...meter}
            >
                <Icon className="h-4 w-4 shrink-0 text-foreground overlay-text" aria-hidden />
                <div className="relative overflow-hidden rounded-full bg-muted" style={{ width: size * 1.25, height: stroke + 1.5 }}>
                    <div
                        className="absolute inset-y-0 left-0 rounded-full transition-[width,background-color] ease-linear"
                        style={{ width: `${clamped}%`, background: color, transitionDuration: sweep }}
                    />
                </div>
            </div>
        )
    }

    if (shape === "circle") {
        const radius = size / 2 - stroke
        const circumference = radius * 2 * Math.PI
        const offset = circumference * (1 - clamped / 100)
        return (
            <div
                className={cn("hud-panel relative flex shrink-0 items-center justify-center rounded-full", critical && "animate-pulse")}
                style={{ width: panelSize, height: panelSize }}
                {...meter}
            >
                <svg width={size} height={size} className="-rotate-90">
                    <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="hsl(var(--muted))" strokeWidth={stroke} />
                    <circle
                        cx={size / 2}
                        cy={size / 2}
                        r={radius}
                        fill="none"
                        stroke={color}
                        strokeWidth={stroke}
                        strokeLinecap="round"
                        strokeDasharray={circumference}
                        strokeDashoffset={offset}
                        className="transition-[stroke-dashoffset,stroke] ease-linear"
                        style={{ transitionDuration: sweep }}
                    />
                </svg>
                <Icon className="absolute h-4 w-4 text-foreground overlay-text" aria-hidden />
            </div>
        )
    }

    // Outline shapes draw their own panel inside the SVG: .hud-panel's CSS
    // border and shadow can only follow a rectangle or a rounded rectangle.
    const geometry = shapeGeometry(shape, panelSize)
    const meterInset = PANEL_PADDING + stroke / 2 + 1
    const meterPath = geometry.path(meterInset)
    const [iconX, iconY] = geometry.iconCenter
    const iconSize = shape === "triangle" || shape === "diamond" ? 14 : 16

    return (
        <div
            className={cn("relative shrink-0", critical && "animate-pulse")}
            style={{ width: geometry.width, height: geometry.height, filter: "drop-shadow(0 4px 10px rgb(0 0 0 / 32%))" }}
            {...meter}
        >
            <svg width={geometry.width} height={geometry.height} className="block overflow-visible">
                <path d={geometry.path(0.5)} fill="hsl(var(--hud))" stroke="hsl(var(--border) / 0.72)" strokeWidth={1} strokeLinejoin="round" />
                <path d={meterPath} fill="none" stroke="hsl(var(--muted))" strokeWidth={stroke} strokeLinejoin="round" />
                <path
                    d={meterPath}
                    fill="none"
                    stroke={color}
                    strokeWidth={stroke}
                    strokeLinejoin="round"
                    strokeLinecap={clamped > 0 ? "round" : "butt"}
                    pathLength={100}
                    strokeDasharray="100 100"
                    strokeDashoffset={100 - clamped}
                    className="transition-[stroke-dashoffset,stroke] ease-linear"
                    style={{ transitionDuration: sweep }}
                />
            </svg>
            <Icon
                className="absolute text-foreground overlay-text"
                style={{ width: iconSize, height: iconSize, left: iconX - iconSize / 2, top: iconY - iconSize / 2 }}
                aria-hidden
            />
        </div>
    )
}
