/* screens-system.jsx — App 菜单与诊断入口、最小窗口 900×600 */
(function () {
  function AppMenus() {
    return (
      <div className="desktop-scene" style={{ width: 940, height: 560 }}>
        <div className="menubar-strip" style={{ justifyContent: "flex-start", gap: 2, padding: "0 10px" }}>
          <span style={{ marginRight: 10, fontWeight: 700 }}></span>
          <span className="menubar-item open" style={{ fontWeight: 700, padding: "2px 8px" }}>EchoSub</span>
          <span className="menubar-item open" style={{ padding: "2px 8px", opacity: 0.85 }} lang="zh">播放</span>
          <span style={{ flex: 1 }} />
          <IconCaptions size={13} style={{ color: "var(--accent-strong)" }} />
        </div>

        {/* 设计说明页：两个菜单同时展开仅为展示 */}
        <div className="appmenu" style={{ left: 34, top: 30 }}>
          <button className="ctx-item" lang="zh">关于 EchoSub</button>
          <div className="ctx-sep" />
          <button className="ctx-item"><span lang="zh">打开诊断日志</span><IconDocText size={12} /></button>
          <button className="ctx-item"><span lang="zh">显示本地数据文件夹</span><IconFolder size={12} /></button>
          <div className="ctx-sep" />
          <button className="ctx-item"><span lang="zh">设置…</span><kbd>⌘,</kbd></button>
          <div className="ctx-sep" />
          <button className="ctx-item"><span lang="zh">退出 EchoSub</span><kbd>⌘Q</kbd></button>
        </div>

        <div className="appmenu" style={{ left: 154, top: 30 }}>
          <button className="ctx-item"><span lang="zh">显示 / 隐藏悬浮字幕</span><kbd>⇧⌘F</kbd></button>
          <button className="ctx-item"><span lang="zh">显示 / 隐藏桌面歌词</span><kbd>⇧⌘D</kbd></button>
          <button className="ctx-item"><span lang="zh">锁定 / 解锁桌面歌词</span><kbd>⇧⌘L</kbd></button>
        </div>

        <div className="lock-hint" style={{ left: 24, bottom: 24, maxWidth: 480 }}>
          <IconDocText size={13} style={{ color: "var(--accent-strong)", flexShrink: 0 }} />
          <span lang="zh">诊断日志（diagnostics.jsonl）是排查长视频翻译进度的主要途径；桌面歌词锁定后从这里或 ⇧⌘L 解锁。</span>
        </div>
      </div>
    );
  }

  function MinWindow({ player }) {
    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
        <MainWindow player={player} variant="playing" width={900} height={600} />
        <div className="anno" style={{ position: "static" }} lang="zh">
          最小尺寸 900 × 600：中栏保持 ≥ 360，左右栏可被压缩到各自最小宽度
        </div>
      </div>
    );
  }

  Object.assign(window, { AppMenus, MinWindow });
})();
