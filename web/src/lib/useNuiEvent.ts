import { useEffect, useRef } from "react"

import type { NuiWireMessage } from "./types"

/**
 * Subscribes to messages sent from Lua via QB.nui.send for a single `action`
 * name. `handler` receives the message's `data` verbatim.
 *
 * The `window` listener is only ever attached/removed when `action` changes
 * (or on mount/unmount) -- the latest `handler` is called via a ref rather
 * than being a dependency itself, so passing a fresh inline arrow every
 * render doesn't tear down and re-add the listener on every re-render.
 *
 * Deliberately no event.source/event.origin check -- see kora_lib's own
 * web/src/lib/useNuiEvent.ts for why that's a trap, not a hardening measure:
 * FiveM posts SendNUIMessage from the game's own NUI window (origin
 * "nui://game"), not from this page, so any source/origin gate silently
 * discards every real message from Lua.
 */
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
    const handlerRef = useRef(handler)
    handlerRef.current = handler

    useEffect(() => {
        function listener(event: MessageEvent<NuiWireMessage<T>>) {
            if (event.data?.action === action) {
                handlerRef.current(event.data.data)
            }
        }

        window.addEventListener("message", listener)
        return () => window.removeEventListener("message", listener)
    }, [action])
}
