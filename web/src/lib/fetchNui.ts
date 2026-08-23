declare global {
    interface Window {
        GetParentResourceName?: () => string
        invokeNative?: (...args: unknown[]) => unknown
    }
}

// True when running outside the CEF NUI frame (e.g. `pnpm dev` in a normal
// browser) -- lets components render/develop without a game to talk to.
// Same convention as qblib's own web/src/lib/fetchNui.ts.
export const isBrowserEnv = typeof window.invokeNative !== "function"

function resourceName(): string {
    return window.GetParentResourceName ? window.GetParentResourceName() : "qbhud"
}

/**
 * Calls an NUI callback registered via QB.nui.registerCallback (Lua side).
 * In a plain browser (isBrowserEnv) this never reaches Lua -- it resolves an
 * empty object so components stay usable in isolation during development.
 */
export async function fetchNui<T = unknown>(callbackName: string, data: unknown = {}): Promise<T> {
    if (isBrowserEnv) {
        return {} as T
    }

    const response = await fetch(`https://${resourceName()}/${callbackName}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data),
    })

    if (!response.ok) {
        throw new Error(`NUI callback '${callbackName}' failed: ${response.status}`)
    }

    return (await response.json()) as T
}
