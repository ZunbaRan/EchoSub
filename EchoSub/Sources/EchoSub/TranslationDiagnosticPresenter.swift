import AppKit

enum TranslationDiagnosticPresenter {
    static func present(
        segment: SubtitleSegment,
        videoID: String,
        state: AppState,
        parentWindow: NSWindow?
    ) {
        let diagnostic = state.translationDiagnostic(for: segment.id, videoID: videoID)
        let alert = NSAlert()
        alert.alertStyle = diagnostic?.phase == .failed ? .warning : .informational
        alert.messageText = diagnostic?.phase.label ?? "本次启动后尚无翻译记录"
        alert.informativeText = diagnostic?.detailText(for: segment) ?? [
            "字幕 ID：\(segment.id)",
            "说明：本次启动后还没有请求过此句。你仍可打开完整日志查看此前请求。",
            "原文：\(segment.original)",
            "当前译文：\(segment.effectiveTranslation ?? "无")",
        ].joined(separator: "\n")
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "打开完整日志")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertSecondButtonReturn {
                DiagnosticLogger.shared.record("diagnostics.opened_for_cue", fields: [
                    "video_id": videoID,
                    "cue_id": segment.id,
                ])
                NSWorkspace.shared.open(DiagnosticLogger.shared.fileURL)
            }
        }
        if let parentWindow {
            alert.beginSheetModal(for: parentWindow, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}
