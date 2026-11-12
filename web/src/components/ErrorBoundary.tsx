import { Component, type ErrorInfo, type ReactNode } from "react"

interface Props {
    children: ReactNode
}

interface State {
    hasError: boolean
}

/**
 * Root error boundary: a render-phase crash in any one HUD element must not
 * unmount the whole overlay. The overlay is headless, so the fallback
 * renders nothing; the error is logged to the NUI console. Same convention
 * as kora_lib's own web/src/components/ErrorBoundary.tsx.
 */
export class ErrorBoundary extends Component<Props, State> {
    state: State = { hasError: false }

    static getDerivedStateFromError(): State {
        return { hasError: true }
    }

    componentDidCatch(error: Error, info: ErrorInfo) {
        console.error("[qb-hud] NUI render error:", error, info.componentStack)
    }

    render() {
        if (this.state.hasError) return null
        return this.props.children
    }
}
