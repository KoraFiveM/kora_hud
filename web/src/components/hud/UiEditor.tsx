import { useEffect, useMemo, useRef, useState } from "react"
import { AlertTriangle, ArrowDownToLine, ArrowUpToLine, Check, RotateCcw, X } from "lucide-react"

import { cn } from "@/lib/cn"
import { useHudLayout, useLocale } from "@/lib/hudState"
import type { HudLayoutOffset, UiElementDef, UiSettingDef, UiSettingValue } from "@/lib/types"
import { HUD_SECTIONS, clampDelta, layoutViewport, snapDragAngle, snapOffsetToGrid } from "./LayoutEditor"

/**
 * The unified /ui editor: a panel to pick an element and change its
 * visibility, size and settings, plus an outline proxy for every element
 * another resource renders (kora_chat, kora_inventory) and for the minimap,
 * which the game draws. kora_hud's own sections stay MovableSections.
 *
 * Proxies are positioned exactly like the owner positions its real element:
 * `rect` is the zero point (viewport fractions), the offset is added in
 * viewport fractions and the scale grows from `origin`. Every drag and scale
 * is clamped so the whole box stays on screen.
 */

interface PanelElement {
    id: string
    label: string
    group: string
    hideable: boolean
    scalable: boolean
    scaleMin: number
    scaleMax: number
    settings: UiSettingDef[]
}

/** kora_hud's own sections, in the order the dropdown lists them. */
const BUILTIN_ELEMENTS: PanelElement[] = [
    { id: HUD_SECTIONS.gauges, label: "Gauges", group: "HUD", hideable: true, scalable: true, scaleMin: 0.75, scaleMax: 1.5, settings: [] },
    { id: HUD_SECTIONS.vehicle, label: "Vehicle", group: "HUD", hideable: true, scalable: true, scaleMin: 0.75, scaleMax: 1.5, settings: [] },
    { id: HUD_SECTIONS.identity, label: "Player info and money", group: "HUD", hideable: true, scalable: true, scaleMin: 0.75, scaleMax: 1.5, settings: [] },
    { id: HUD_SECTIONS.status, label: "Status effects", group: "HUD", hideable: true, scalable: true, scaleMin: 0.75, scaleMax: 1.5, settings: [] },
]
/** Shown only while an older kora_chat (one that does not register) runs. */
const LEGACY_CHAT: PanelElement = { id: HUD_SECTIONS.chatInput, label: "Chat input", group: "Chat", hideable: false, scalable: true, scaleMin: 0.75, scaleMax: 1.5, settings: [] }

function originFactors(origin: string): [number, number] {
    const [ox, oy] = origin.split(" ")
    return [ox === "right" ? 1 : ox === "center" ? 0.5 : 0, oy === "bottom" ? 1 : oy === "center" ? 0.5 : 0]
}

/** Keeps the scaled box of `def` inside the viewport (all in fractions). */
export function clampProxyOffset(def: UiElementDef, offset: HudLayoutOffset, scale: number): HudLayoutOffset {
    const [fx, fy] = originFactors(def.origin)
    const width = def.rect.w * scale
    const height = def.rect.h * scale
    const left = def.rect.x + fx * def.rect.w * (1 - scale)
    const top = def.rect.y + fy * def.rect.h * (1 - scale)
    const axis = (value: number, start: number, size: number) =>
        size >= 1 ? -start : clampDelta(value, -start, 1 - size - start)
    return {
        x: clampDelta(axis(offset.x, left, width), -1, 1),
        y: clampDelta(axis(offset.y, top, height), -1, 1),
    }
}

function proxyTransform(offset: HudLayoutOffset, scale: number): string {
    const viewport = layoutViewport()
    return `translate(${offset.x * viewport.width}px, ${offset.y * viewport.height}px) scale(${scale})`
}

/** Re-render on resize: proxies are laid out in viewport pixels. */
function useViewportSize() {
    const [size, setSize] = useState({ width: window.innerWidth, height: window.innerHeight })
    useEffect(() => {
        const onResize = () => setSize({ width: window.innerWidth, height: window.innerHeight })
        window.addEventListener("resize", onResize)
        return () => window.removeEventListener("resize", onResize)
    }, [])
    return size
}

/** Outline box for one registered element; drag to move, corner to scale. */
export function ExternalProxy({ def }: { def: UiElementDef }) {
    const t = useLocale()
    const layout = useHudLayout()
    const nodeRef = useRef<HTMLDivElement>(null)
    useViewportSize()
    const viewport = layoutViewport()
    const scale = layout.scales[def.id] ?? 1
    const offset = layout.offsets[def.id] ?? def.defaultOffset ?? { x: 0, y: 0 }
    const hidden = layout.editor.allowHide && layout.hidden[def.id] === true
    const selected = layout.selected === def.id
    const [fx, fy] = originFactors(def.origin)

    function onMoveStart(event: React.MouseEvent<HTMLDivElement>) {
        event.preventDefault()
        layout.select(def.id)
        if (!def.movable) return
        const node = nodeRef.current
        if (!node) return
        const startX = event.clientX
        const startY = event.clientY
        const base = clampProxyOffset(def, offset, scale)
        let latest = base

        const onMove = (moveEvent: MouseEvent) => {
            let deltaX = moveEvent.clientX - startX
            let deltaY = moveEvent.clientY - startY
            if (moveEvent.shiftKey) {
                const snapped = snapDragAngle(deltaX, deltaY)
                deltaX = snapped.x
                deltaY = snapped.y
            }
            let next = { x: base.x + deltaX / window.innerWidth, y: base.y + deltaY / window.innerHeight }
            if (moveEvent.ctrlKey) next = { x: snapOffsetToGrid(next.x), y: snapOffsetToGrid(next.y) }
            latest = clampProxyOffset(def, next, scale)
            // Direct DOM write while dragging, same reasoning as MovableSection.
            node.style.transform = proxyTransform(latest, scale)
            layout.preview(def.id, false, { x: latest.x, y: latest.y })
        }
        const onUp = () => {
            window.removeEventListener("mousemove", onMove)
            window.removeEventListener("mouseup", onUp)
            if (latest === base) return
            layout.commitOffset(def.id, latest)
            layout.preview(def.id, true, { x: latest.x, y: latest.y })
        }
        window.addEventListener("mousemove", onMove)
        window.addEventListener("mouseup", onUp)
    }

    function onScaleStart(event: React.MouseEvent<HTMLButtonElement>) {
        event.preventDefault()
        event.stopPropagation()
        layout.select(def.id)
        const node = nodeRef.current
        if (!node || !def.scalable) return
        const startX = event.clientX
        const base = scale
        // Dragging away from the origin grows the element.
        const direction = fx === 1 ? -1 : 1
        const boxWidth = Math.max(1, def.rect.w * window.innerWidth)
        let latestScale = base
        let latestOffset = offset

        const onMove = (moveEvent: MouseEvent) => {
            latestScale = clampDelta(base + (direction * (moveEvent.clientX - startX)) / boxWidth, def.scaleMin, def.scaleMax)
            latestOffset = clampProxyOffset(def, offset, latestScale)
            node.style.transform = proxyTransform(latestOffset, latestScale)
            layout.preview(def.id, false, { scale: latestScale, x: latestOffset.x, y: latestOffset.y })
        }
        const onUp = () => {
            window.removeEventListener("mousemove", onMove)
            window.removeEventListener("mouseup", onUp)
            if (latestScale === base) return
            layout.commitScale(def.id, latestScale)
            // Always store the offset with the scale: an element whose default
            // spot is a defaultOffset (chat) must not fall back to its zero point.
            layout.commitOffset(def.id, latestOffset)
            layout.preview(def.id, true, { scale: latestScale, x: latestOffset.x, y: latestOffset.y })
        }
        window.addEventListener("mousemove", onMove)
        window.addEventListener("mouseup", onUp)
    }

    // The corner handle sits on the corner opposite the scale origin.
    const handleX = fx === 1 ? "left-0 -translate-x-1/2" : "right-0 translate-x-1/2"
    const handleY = fy === 1 ? "top-0 -translate-y-1/2" : "bottom-0 translate-y-1/2"

    return (
        <div
            ref={nodeRef}
            onMouseDown={onMoveStart}
            data-ui-proxy={def.id}
            className={cn(
                "pointer-events-auto fixed rounded-lg border bg-[hsl(var(--primary)/8%)]",
                selected ? "border-2 border-solid border-[hsl(var(--primary))]" : "border-dashed border-[hsl(var(--primary)/65%)]",
                def.movable ? "cursor-grab active:cursor-grabbing" : "cursor-default",
                hidden && "opacity-40",
            )}
            style={{
                left: def.rect.x * viewport.width,
                top: def.rect.y * viewport.height,
                width: def.rect.w * viewport.width,
                height: def.rect.h * viewport.height,
                transform: proxyTransform(offset, scale),
                transformOrigin: def.origin,
            }}
        >
            <span className="pointer-events-none absolute left-1.5 top-1.5 flex max-w-[calc(100%-12px)] items-center gap-1 truncate rounded bg-background/90 px-1.5 py-0.5 text-[11px] font-semibold text-foreground">
                {def.label}
                {hidden && <span className="font-normal uppercase tracking-wide text-muted-foreground">· {t("UI.hiddenLabel")}</span>}
                {!def.movable && <span className="font-normal text-muted-foreground">· {t("UI.locked")}</span>}
            </span>
            {def.scalable && (
                <button
                    type="button"
                    aria-label={t("UI.resize", def.label)}
                    title={t("UI.resizeDrag")}
                    onMouseDown={onScaleStart}
                    className={cn("absolute h-4 w-4 min-h-0 rounded-sm border border-primary bg-primary p-0", handleX, handleY, "cursor-nwse-resize")}
                />
            )}
        </div>
    )
}

function Switch({ checked, onChange, label }: { checked: boolean; onChange: (value: boolean) => void; label: string }) {
    return (
        <button
            type="button"
            role="switch"
            aria-checked={checked}
            onClick={() => onChange(!checked)}
            className="flex w-full items-center justify-between gap-3 rounded-md border-0 bg-transparent px-0 py-1 text-left text-sm text-foreground hover:bg-transparent"
        >
            <span>{label}</span>
            <span aria-hidden className={cn("flex h-5 w-9 flex-none items-center rounded-full p-0.5 transition-colors", checked ? "bg-primary" : "bg-border")}>
                <span className={cn("h-4 w-4 rounded-full bg-primary-foreground transition-transform", checked ? "translate-x-4" : "translate-x-0")} />
            </span>
        </button>
    )
}

function formatRange(setting: UiSettingDef, value: number): string {
    if (value === 0 && setting.zeroLabel) return setting.zeroLabel
    const rounded = Math.round(value * 100) / 100
    return setting.unit ? `${rounded}${setting.unit === "%" ? "" : " "}${setting.unit}` : String(rounded)
}

function SettingControl({ id, setting }: { id: string; setting: UiSettingDef }) {
    const layout = useHudLayout()
    const current = layout.settings[id]?.[setting.key]
    const value: UiSettingValue = current ?? setting.default

    if (setting.type === "toggle") {
        return <Switch checked={value === true} label={setting.label} onChange={(next) => layout.setSetting(id, setting.key, next)} />
    }
    if (setting.type === "select") {
        return (
            <div className="flex flex-col gap-1.5">
                <span className="text-sm text-foreground">{setting.label}</span>
                <div className="flex flex-wrap gap-1">
                    {(setting.options ?? []).map((option) => (
                        <button
                            key={option.value}
                            type="button"
                            onClick={() => layout.setSetting(id, setting.key, option.value)}
                            className={cn(
                                "min-h-8 rounded-md px-2.5 py-1 text-xs",
                                value === option.value ? "border-primary bg-primary text-primary-foreground hover:bg-primary" : "",
                            )}
                        >
                            {option.label}
                        </button>
                    ))}
                </div>
            </div>
        )
    }
    const number = typeof value === "number" ? value : Number(setting.default)
    return (
        <label className="flex flex-col gap-1">
            <span className="flex items-center justify-between text-sm text-foreground">
                <span>{setting.label}</span>
                <span className="font-mono text-xs text-muted-foreground">{formatRange(setting, number)}</span>
            </span>
            <input
                type="range"
                min={setting.min}
                max={setting.max}
                step={setting.step ?? "any"}
                value={number}
                onChange={(event) => layout.setSetting(id, setting.key, Number(event.target.value))}
                className="w-full border-0 bg-transparent p-0"
            />
            {setting.description && <span className="text-xs text-muted-foreground">{setting.description}</span>}
        </label>
    )
}

/** The /ui panel: element picker, per-element controls, Save/Cancel/Reset. */
export function EditorPanel() {
    const t = useLocale()
    const layout = useHudLayout()
    const [dock, setDock] = useState<"top" | "bottom">("top")
    const [confirmingReset, setConfirmingReset] = useState(false)

    useEffect(() => {
        if (!layout.editing) return
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key === "Escape") layout.cancel()
        }
        window.addEventListener("keydown", onKeyDown)
        return () => window.removeEventListener("keydown", onKeyDown)
    }, [layout.editing, layout.cancel])

    useEffect(() => {
        if (!confirmingReset) return
        const timer = window.setTimeout(() => setConfirmingReset(false), 4000)
        return () => window.clearTimeout(timer)
    }, [confirmingReset])

    const options = useMemo<PanelElement[]>(() => {
        const registered = layout.elements.map((element) => ({
            id: element.id, label: element.label, group: element.group, hideable: element.hideable,
            scalable: element.scalable, scaleMin: element.scaleMin, scaleMax: element.scaleMax,
            settings: Array.isArray(element.settings) ? element.settings : [],
        }))
        const chatRegistered = registered.some((element) => element.id === HUD_SECTIONS.chatInput)
        const builtinLabels: Record<string, string> = {
            [HUD_SECTIONS.gauges]: t("UI.gauge"),
            [HUD_SECTIONS.vehicle]: t("UI.vehicle"),
            [HUD_SECTIONS.identity]: t("UI.playerInfoMoney"),
            [HUD_SECTIONS.status]: t("UI.statusEffects"),
        }
        const builtin = BUILTIN_ELEMENTS.map((element) => ({ ...element, label: builtinLabels[element.id], group: t("UI.hudGroup") }))
        const legacyChat = { ...LEGACY_CHAT, label: t("UI.chatInput"), group: t("UI.chatGroup") }
        return [...builtin, ...(chatRegistered ? [] : [legacyChat]), ...registered]
    }, [layout.elements, t])

    const groups = useMemo(() => {
        const out = new Map<string, PanelElement[]>()
        for (const option of options) out.set(option.group, [...(out.get(option.group) ?? []), option])
        return [...out.entries()]
    }, [options])

    if (!layout.editing) return null

    const current = options.find((option) => option.id === layout.selected)
    const scale = current ? layout.scales[current.id] ?? 1 : 1
    const isHidden = current ? layout.hidden[current.id] === true : false
    const external = current ? layout.elements.find((element) => element.id === current.id) : undefined

    function setScale(value: number, final: boolean) {
        if (!current) return
        layout.commitScale(current.id, value)
        if (external) {
            const offset = layout.offsets[external.id] ?? external.defaultOffset ?? { x: 0, y: 0 }
            const clamped = clampProxyOffset(external, offset, value)
            // Stored with the scale even when unchanged, see ExternalProxy.
            if (!(external.id in layout.offsets) || clamped.x !== offset.x || clamped.y !== offset.y) {
                layout.commitOffset(external.id, clamped)
            }
            layout.preview(external.id, final, { scale: value, x: clamped.x, y: clamped.y })
        }
    }

    return (
        <div className="pointer-events-none fixed inset-0 bg-black/45">
            <div
                className={cn(
                    "hud-panel pointer-events-auto absolute left-1/2 flex w-[360px] max-w-[calc(100%-1rem)] -translate-x-1/2 flex-col gap-3 rounded-xl p-3 text-foreground",
                    dock === "top" ? "top-3" : "bottom-3",
                )}
                role="dialog"
                aria-label={t("UI.uiLayoutEditor")}
            >
                <div className="flex items-center justify-between gap-2">
                    <div className="flex flex-col">
                        <span className="text-sm font-semibold">{t("UI.uiLayout")}</span>
                        <span className="text-[11px] text-muted-foreground">{t("UI.editorHint")}</span>
                    </div>
                    <button
                        type="button"
                        aria-label={dock === "top" ? t("UI.movePanelBottom") : t("UI.movePanelTop")}
                        title={dock === "top" ? t("UI.movePanelToBottom") : t("UI.movePanelToTop")}
                        onClick={() => setDock(dock === "top" ? "bottom" : "top")}
                        className="flex h-8 w-8 min-h-8 items-center justify-center rounded-md p-0"
                    >
                        {dock === "top" ? <ArrowDownToLine className="h-4 w-4" aria-hidden /> : <ArrowUpToLine className="h-4 w-4" aria-hidden />}
                    </button>
                </div>

                <select
                    aria-label={t("UI.elementToCustomise")}
                    value={current?.id ?? ""}
                    onChange={(event) => layout.select(event.target.value || null)}
                    className="h-9 w-full rounded-md text-sm"
                >
                    <option value="">{t("UI.chooseElement")}</option>
                    {groups.map(([group, items]) => (
                        <optgroup key={group} label={group}>
                            {items.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
                        </optgroup>
                    ))}
                </select>

                {current ? (
                    <div className="flex flex-col gap-3 rounded-lg border border-border/70 bg-background/40 p-3">
                        {layout.editor.allowHide && current.hideable && (
                            <Switch
                                checked={!isHidden}
                                label={isHidden ? t("UI.hiddenLabel") : t("UI.visible")}
                                onChange={(visible) => layout.setHidden(current.id, !visible)}
                            />
                        )}
                        {current.scalable && (
                            <label className="flex flex-col gap-1">
                                <span className="flex items-center justify-between text-sm">
                                    <span>{t("UI.size")}</span>
                                    <span className="font-mono text-xs text-muted-foreground">{Math.round(scale * 100)}%</span>
                                </span>
                                <input
                                    type="range"
                                    min={current.scaleMin}
                                    max={current.scaleMax}
                                    step={0.01}
                                    value={scale}
                                    onChange={(event) => setScale(Number(event.target.value), false)}
                                    onMouseUp={(event) => setScale(Number((event.target as HTMLInputElement).value), true)}
                                    onKeyUp={(event) => setScale(Number((event.target as HTMLInputElement).value), true)}
                                    className="w-full border-0 bg-transparent p-0"
                                />
                            </label>
                        )}
                        {current.id === "minimap" && layout.minimapVehicleOnlyAllowed && (
                            <Switch
                                checked={layout.minimapVehicleOnly}
                                label={t("UI.onlyInVehicle")}
                                onChange={(value) => layout.setMinimapVehicleOnly(value)}
                            />
                        )}
                        {current.settings.map((setting) => <SettingControl key={setting.key} id={current.id} setting={setting} />)}
                        <button
                            type="button"
                            onClick={() => layout.resetElement(current.id)}
                            className="flex h-8 items-center justify-center gap-1.5 rounded-md text-xs"
                        >
                            <RotateCcw className="h-3.5 w-3.5" aria-hidden /> {t("UI.reset", current.label)}
                        </button>
                    </div>
                ) : (
                    <p className="m-0 text-xs text-muted-foreground">
                        {t("UI.emptyEditorHint")}
                    </p>
                )}

                <div className="flex items-center gap-2">
                    <button
                        type="button"
                        onClick={layout.confirm}
                        className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-md border-primary bg-primary text-sm font-semibold text-primary-foreground hover:bg-primary"
                    >
                        <Check className="h-4 w-4" aria-hidden /> {t("UI.save")}
                    </button>
                    <button
                        type="button"
                        onClick={layout.cancel}
                        className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-md text-sm"
                    >
                        <X className="h-4 w-4" aria-hidden /> {t("UI.cancel")}
                    </button>
                    <button
                        type="button"
                        onClick={() => {
                            if (!confirmingReset) {
                                setConfirmingReset(true)
                                return
                            }
                            setConfirmingReset(false)
                            layout.resetToDefaults()
                        }}
                        className={cn(
                            "flex h-9 flex-1 items-center justify-center gap-1.5 rounded-md text-sm",
                            confirmingReset && "border-destructive text-destructive",
                        )}
                    >
                        {confirmingReset ? <AlertTriangle className="h-4 w-4" aria-hidden /> : <RotateCcw className="h-4 w-4" aria-hidden />}
                        {confirmingReset ? t("UI.confirmReset") : t("UI.resetAll")}
                    </button>
                </div>
            </div>
        </div>
    )
}
