import { useNuiEvent } from "@/lib/useNuiEvent"

interface SeatbeltSoundPayload {
    /** File name inside web/build/sounds, without a path. */
    file: string
    /** 0.0 - 1.0. */
    volume: number
}

/**
 * Headless. Plays the buckle/unbuckle clip Lua asks for. Mounted at the App
 * root, outside the visibility gate, so the sound still plays while the HUD is
 * hidden or being edited. Lua decides WHEN and at what volume; the file name is
 * reduced to a bare name here so a stray config value cannot reach outside
 * ./sounds/.
 */
export function SeatbeltSound() {
    useNuiEvent<SeatbeltSoundPayload>("kora_hud:seatbeltSound", (data) => {
        const file = typeof data?.file === "string" ? data.file.replace(/[^\w.-]/g, "") : ""
        if (!file) return
        const volume = Math.min(1, Math.max(0, Number(data.volume) || 0))
        const audio = new Audio(`./sounds/${file}`)
        audio.volume = volume
        audio.play().catch(() => {})
    })
    return null
}
