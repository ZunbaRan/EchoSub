/* screens-floating.jsx — 悬浮字幕窗（默认 / Pin / 手动滚动）与桌面歌词（编辑 / 锁定） */
(function () {
  const { useState, useEffect, useRef } = React;

  /* ---------------- 悬浮字幕窗 ---------------- */
  function FloatingWindow({ variant, player }) {
    // variant: "default" | "pinned" | "scrolled"
    const [pinned, setPinned] = useState(variant === "pinned");
    const [mode, setMode] = useState("both");
    const [follow, setFollow] = useState(variant !== "scrolled");
    const [size, setSize] = useState(0); // -1, 0, +1
    const cur = currentSubtitleAt(player.time);
    const curIdx = SUBTITLES.findIndex((s) => s.id === cur.id);
    const from = follow ? Math.max(0, curIdx - 1) : Math.max(0, curIdx - 4);
    const to = follow ? Math.min(SUBTITLES.length, curIdx + 3) : Math.min(SUBTITLES.length, curIdx + 2);
    const visible = SUBTITLES.slice(from, to);
    const curRef = useRef(null);

    useEffect(() => {
      if (follow && curRef.current) curRef.current.scrollIntoView({ block: "center", behavior: "smooth" });
    }, [cur.id, follow]);

    const scale = size === 1 ? 1.14 : size === -1 ? 0.88 : 1;

    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
        <div className="floatwin" style={{ width: 470, height: 320 }}>
          <div className="floatbar float-fadectl">
            <IconBtn title={pinned ? "取消 Pin" : "Pin 置顶"} on={pinned} onClick={() => setPinned(!pinned)}>
              {pinned ? <IconPinFill size={13} /> : <IconPin size={13} />}
            </IconBtn>
            <span className="ic" style={{ padding: "0 3px" }}><IconTextSize size={13} /></span>
            <IconBtn title="字号减小" onClick={() => setSize(Math.max(-1, size - 1))}><span style={{ fontSize: 10, fontWeight: 700 }}>A−</span></IconBtn>
            <IconBtn title="字号增大" onClick={() => setSize(Math.min(1, size + 1))}><span style={{ fontSize: 13, fontWeight: 700 }}>A+</span></IconBtn>
            <Seg
              options={[{ value: "en", label: "原文" }, { value: "zh", label: "中文" }, { value: "both", label: "双语" }]}
              value={mode} onChange={setMode}
            />
            <div style={{ flex: 1 }} />
            {pinned && <span className="pinflag">PINNED</span>}
            <IconBtn title="恢复自动跟随" on={follow} onClick={() => setFollow(!follow)}><IconFollow size={13} /></IconBtn>
            <IconBtn title="切换到桌面歌词"><IconLyrics size={13} /></IconBtn>
            <IconBtn title="关闭"><IconX size={13} /></IconBtn>
          </div>
          <div className="float-body" onWheel={() => follow && setFollow(false)}>
            {visible.map((r) => (
              <div key={r.id} ref={r.id === cur.id ? curRef : null}
                   className={"f-row" + (r.id === cur.id ? " cur" : "")}
                   onClick={() => player.setTime(r.start)}
                   style={{ transform: `scale(${scale})`, transformOrigin: "left center" }}>
                {mode !== "zh" && <div className="f-en" lang="en">{r.en}</div>}
                {mode !== "en" && <div className="f-zh" lang="zh">{r.zh}</div>}
              </div>
            ))}
          </div>
        </div>
        {!follow && (
          <div className="anno" style={{ position: "static" }} lang="zh">
            手动滚动后自动跟随已暂停 · 点击 <IconFollow size={10} style={{ verticalAlign: "-1px" }} /> 恢复
          </div>
        )}
      </div>
    );
  }

  /* ---------------- 桌面歌词 ---------------- */
  function FakeDesktopApp({ style, title, lines }) {
    return (
      <div className="desktop-app" style={style}>
        <div style={{
          height: 30, display: "flex", alignItems: "center", gap: 6, padding: "0 10px",
          borderBottom: "1px solid rgba(255,255,255,0.07)",
        }}>
          <div className="tlights" style={{ transform: "scale(0.8)", transformOrigin: "left center" }}>
            <div className="tlight r" /><div className="tlight y" /><div className="tlight g" />
          </div>
          <span style={{ fontSize: 11, color: "rgba(255,255,255,0.5)" }}>{title}</span>
        </div>
        <div style={{ padding: "14px 16px", display: "flex", flexDirection: "column", gap: 9 }}>
          {lines.map((w, i) => (
            <div key={i} style={{
              height: 8, borderRadius: 4, background: "rgba(255,255,255,0.1)", width: w + "%",
            }} />
          ))}
        </div>
      </div>
    );
  }

  function DesktopLyrics({ variant, player }) {
    // variant: "edit" | "locked"
    const [locked, setLocked] = useState(variant === "locked");
    const cur = currentSubtitleAt(player.time);
    return (
      <div className="desktop-scene" style={{ width: 940, height: 580 }}>
        <div className="menubar-strip">
          <span>EchoSub</span><span style={{ opacity: 0.6 }}>编辑</span><span style={{ opacity: 0.6 }}>窗口</span>
          <IconCaptions size={13} style={{ color: "var(--accent-strong)" }} />
        </div>

        <FakeDesktopApp title="学习笔记 — Obsidian" style={{ left: 60, top: 60, width: 430, height: 300 }}
                        lines={[72, 88, 45, 80, 60, 30]} />
        <FakeDesktopApp title="YouTube — Safari" style={{ right: 50, top: 120, width: 380, height: 260 }}
                        lines={[100, 100, 55]} />

        <div style={{ position: "absolute", left: "50%", transform: "translateX(-50%)", bottom: 90, display: "flex", flexDirection: "column", alignItems: "center", gap: 10, maxWidth: "82%" }}>
          {!locked && (
            <div className="lyrics-ctl" style={{ position: "static", transform: "none" }}>
              <IconBtn title="字号减小"><span style={{ fontSize: 10, fontWeight: 700 }}>A−</span></IconBtn>
              <IconBtn title="字号增大"><span style={{ fontSize: 13, fontWeight: 700 }}>A+</span></IconBtn>
              <div className="sep" />
              <IconBtn title="对齐：居中"><IconFollow size={12} style={{ transform: "rotate(90deg)" }} /></IconBtn>
              <IconBtn title="底板透明度"><IconEye size={13} /></IconBtn>
              <IconBtn title="英中顺序"><IconTranslate size={13} /></IconBtn>
              <div className="sep" />
              <IconBtn title="锁定（穿透鼠标）" onClick={() => setLocked(true)}><IconLock size={12} /></IconBtn>
              <IconBtn title="关闭桌面歌词"><IconX size={12} /></IconBtn>
            </div>
          )}
          <div className={"lyrics with-plate" + (locked ? "" : " edit-mode")}
               style={{ position: "static", transform: "none", left: "auto", maxWidth: "100%", cursor: locked ? "default" : "move" }}
               onDoubleClick={() => locked && setLocked(false)}>
            <div className="l-en" lang="en">{cur.en}</div>
            <div className="l-zh" lang="zh">{cur.zh}</div>
          </div>
        </div>

        {locked && (
          <div className="lock-hint" style={{ left: 24, bottom: 24 }}>
            <IconLock size={13} style={{ color: "var(--accent-strong)" }} />
            <span lang="zh">桌面歌词已锁定 · 鼠标穿透，不影响下面的应用 · 按</span>
            <kbd>⌘⇧L</kbd>
            <span lang="zh">或从菜单栏解锁</span>
          </div>
        )}
      </div>
    );
  }

  Object.assign(window, { FloatingWindow, DesktopLyrics });
})();
