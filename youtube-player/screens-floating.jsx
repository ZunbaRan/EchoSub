/* screens-floating.jsx — v0.1.2
   悬浮字幕窗口：两行控制条 / 背景透明度 0–100%（0=真透明无重影）/ 窄窗换行 / 当前句滚到视口 20% 处
   桌面歌词：英中独立字号 / 自动高度 / 带底板·半透明·全透明·锁定 */
(function () {
  const { useState, useEffect, useRef } = React;

  /* ================= 悬浮字幕窗口 ================= */
  function FloatingWindow({ variant, player }) {
    // variant: "default" | "narrow" | "transparent" | "lookup"
    const [pinned, setPinned] = useState(true);
    const [mode, setMode] = useState("both");
    const [follow, setFollow] = useState(true);
    const [enSize, setEnSize] = useState(15);
    const [opacity, setOpacity] = useState(variant === "transparent" ? 0 : 96);
    const [rowMenu, setRowMenu] = useState(null);
    const [glossAdded, setGlossAdded] = useState(false);
    const bodyRef = useRef(null);
    const curRef = useRef(null);
    const hostRef = useRef(null);

    // lookup 演示固定使用含 gossip 的句子，保证选中词与直译结果确定
    const cur = variant === "lookup" ? SUBTITLES.find((s) => s.id === "s07") : currentSubtitleAt(player.time);
    const curIdx = SUBTITLES.findIndex((s) => s.id === cur.id);
    const visible = SUBTITLES.slice(Math.max(0, curIdx - 3), Math.min(SUBTITLES.length, curIdx + 5));

    // 选词演示：在当前句英文中高亮一个生词
    const PROBE = ["gossip", "judging", "negativity", "onwards", "viral", "complaining", "deadly sins", "habits", "assembled", "exhaustive"];
    const EXTRA_GLOSS = { "deadly sins": "七宗罪（宗教典故）", habits: "习惯", assembled: "汇集；整理", exhaustive: "详尽的；无遗的" };
    const selWord = PROBE.find((p) => cur.en.includes(p)) || cur.en.split(" ")[0];
    const selGloss = (VOCAB_LIST.find((v) => v.w === selWord) || {}).g || EXTRA_GLOSS[selWord] || "（直译结果）";
    const renderEnWithSelection = (text) => {
      const i = text.indexOf(selWord);
      return (
        <React.Fragment>
          {text.slice(0, i)}<span className="hl-select">{selWord}</span>{text.slice(i + selWord.length)}
        </React.Fragment>
      );
    };

    // 自动跟随：当前句滚到视口顶部以下约 20% 的位置
    useEffect(() => {
      if (!follow || !curRef.current || !bodyRef.current) return;
      const body = bodyRef.current;
      const rowTop = curRef.current.offsetTop;
      body.scrollTo({ top: rowTop - body.clientHeight * 0.2, behavior: "smooth" });
    }, [cur.id, follow]);

    const winW = variant === "narrow" ? 320 : 470;
    const winH = variant === "narrow" ? 360 : 320;
    const zhSize = Math.max(11, enSize - 3);
    const alpha = (opacity / 100);

    const winStyle = {
      width: winW, height: winH,
      overflow: variant === "lookup" ? "visible" : undefined,
      background: `rgba(30,30,34,${(0.82 * alpha).toFixed(3)})`,
      boxShadow: alpha === 0
        ? "none"
        : "0 12px 36px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(0,0,0,0.5), inset 0 0 0 0.5px rgba(255,255,255,0.12)",
      backdropFilter: alpha === 0 ? "none" : "blur(30px) saturate(160%)",
      WebkitBackdropFilter: alpha === 0 ? "none" : "blur(30px) saturate(160%)",
    };

    const openRowMenu = (e, row) => {
      e.preventDefault();
      const host = hostRef.current.getBoundingClientRect();
      setRowMenu({ x: e.clientX - host.left, y: e.clientY - host.top, row });
    };

    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
        <div className="floatwin" ref={hostRef} style={{ ...winStyle, position: "relative" }}>
          {/* 第一行控制条 */}
          <div className="floatbar float-fadectl">
            <IconBtn title={pinned ? "取消 Pin" : "Pin 置顶"} on={pinned} onClick={() => setPinned(!pinned)}>
              {pinned ? <IconPinFill size={13} /> : <IconPin size={13} />}
            </IconBtn>
            <IconBtn title="字号减小（最小 12）" onClick={() => setEnSize(Math.max(12, enSize - 1))}><span style={{ fontSize: 10, fontWeight: 700 }}>A−</span></IconBtn>
            <IconBtn title="字号增大（最大 36）" onClick={() => setEnSize(Math.min(36, enSize + 1))}><span style={{ fontSize: 13, fontWeight: 700 }}>A+</span></IconBtn>
            <Seg
              options={[{ value: "en", label: "原文" }, { value: "zh", label: "中文" }, { value: "both", label: "双语" }]}
              value={mode} onChange={setMode}
            />
            <div style={{ flex: 1 }} />
            {pinned && <span className="pinflag">PINNED</span>}
            <IconBtn title="自动跟随" on={follow} onClick={() => setFollow(!follow)}><IconFollow size={13} /></IconBtn>
            <IconBtn title="切换到桌面歌词"><IconLyrics size={13} /></IconBtn>
          </div>
          {/* 第二行：背景透明度 */}
          <div className="floatbar2 float-fadectl">
            <IconOpacity size={12} style={{ color: "rgba(255,255,255,0.55)" }} />
            <div className="slider" style={{ cursor: "pointer" }}
                 onClick={(e) => {
                   const r = e.currentTarget.getBoundingClientRect();
                   setOpacity(Math.round(Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * 100));
                 }}>
              <div className="fillp" style={{ width: opacity + "%" }} />
              <div className="knobp" style={{ left: opacity + "%" }} />
            </div>
            <span className="pct">{opacity}%</span>
          </div>

          <div className="float-body" ref={bodyRef} onWheel={() => follow && setFollow(false)}>
            {visible.map((r) => (
              <div key={r.id}
                   ref={r.id === cur.id ? curRef : null}
                   className={"f-row" + (r.id === cur.id ? " cur" : "")}
                   style={{ opacity: r.id === cur.id ? 1 : 0.72, position: "relative" }}
                   onClick={() => player.setTime(r.start)}
                   onContextMenu={(e) => openRowMenu(e, r)}>
                {mode !== "zh" && (
                  <div className="f-en" lang="en" style={{
                    fontSize: enSize, fontWeight: r.id === cur.id ? 600 : 400,
                    color: alpha === 0 ? "#fff" : undefined,
                    textShadow: alpha === 0 ? "0 1px 8px rgba(0,0,0,0.7)" : "none",
                  }}>
                    {variant === "lookup" && r.id === cur.id ? renderEnWithSelection(r.en) : r.en}
                  </div>
                )}
                {mode !== "en" && (
                  <div className="f-zh" lang="zh" style={{
                    fontSize: zhSize,
                    color: alpha === 0 ? "#FFD54F" : undefined,
                    textShadow: alpha === 0 ? "0 1px 8px rgba(0,0,0,0.7)" : "none",
                  }}>{r.zh || "待补全"}</div>
                )}
                {variant === "lookup" && glossAdded && r.id === cur.id && (
                  <GlossEntries
                    entries={[{ id: "fg1", w: selWord, g: selGloss }]}
                    onRemove={() => setGlossAdded(false)}
                  />
                )}
              </div>
            ))}
          </div>

          {variant === "lookup" && !glossAdded && (
            <SelectionToolbar
              directOnly
              style={{ top: 118, left: 24 }}
              onDirect={() => setGlossAdded(true)}
            />
          )}

          {rowMenu && (
            <div className="ctxmenu" style={{ left: rowMenu.x, top: rowMenu.y }}>
              <button className="ctx-item" onClick={() => setRowMenu(null)}>
                <span lang="zh">{rowMenu.row.zh ? "重新翻译此句" : "补翻此句"}</span>
              </button>
            </div>
          )}

          {/* 悬浮窗仅保留直译：选中后一键追加注释；详解回主窗口查看，不开卡片 */}
        </div>
        {variant === "transparent" && (
          <div className="anno" style={{ position: "static" }} lang="zh">
            背景透明度 0%：真正透明 · 系统窗口阴影已关闭，滚动不残留旧字形
          </div>
        )}
        {variant === "narrow" && (
          <div className="anno" style={{ position: "static" }} lang="zh">
            最小宽度 320：长句自动换行，行高按内容计算，高亮移动不跳动
          </div>
        )}
        {variant === "lookup" && (
          <div className="anno" style={{ position: "static" }} lang="zh">
            悬浮窗仅保留直译：选中单词 → 一键追加注释（点 ✨直译 试试）· 详解回主窗口查看
          </div>
        )}
      </div>
    );
  }

  /* ================= 桌面歌词 ================= */
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
            <div key={i} style={{ height: 8, borderRadius: 4, background: "rgba(255,255,255,0.1)", width: w + "%" }} />
          ))}
        </div>
      </div>
    );
  }

  function DesktopLyrics({ variant, player }) {
    // variant: "edit" | "locked" | "narrow" | "transparent"
    const [locked, setLocked] = useState(variant === "locked");
    const [enSize, setEnSize] = useState(27);
    const [zhSize, setZhSize] = useState(18);
    const [opacity, setOpacity] = useState(variant === "transparent" ? 0 : 72);
    const rawCur = currentSubtitleAt(player.time);
    // 设计稿保护：超长句换用代表性句子，避免演示时溢出场景
    const cur = rawCur.en.length > 140 ? SUBTITLES[6] : rawCur;
    const transparent = opacity === 0;
    const width = variant === "narrow" ? 340 : 570;

    return (
      <div className="desktop-scene" style={{ width: 940, height: 580 }}>
        <div className="menubar-strip">
          <span>EchoSub</span><span style={{ opacity: 0.6 }}>播放</span><span style={{ opacity: 0.6 }}>窗口</span>
          <IconCaptions size={13} style={{ color: "var(--accent-strong)" }} />
        </div>

        <FakeDesktopApp title="学习笔记 — Obsidian" style={{ left: 60, top: 60, width: 430, height: 300 }}
                        lines={[72, 88, 45, 80, 60, 30]} />
        <FakeDesktopApp title="YouTube — Safari" style={{ right: 50, top: 120, width: 380, height: 260 }}
                        lines={[100, 100, 55]} />

        <div style={{
          position: "absolute", left: "50%", transform: "translateX(-50%)",
          ...(locked ? { bottom: 84 } : { top: 108 }),
          display: "flex", flexDirection: "column", alignItems: "center", gap: 12,
          maxWidth: "92%",
        }}>
          {!locked && (
            <div className="lyrics-ctl" style={{ position: "static", transform: "none" }}>
              <IconBtn title="英文减小（12–48）" onClick={() => setEnSize(Math.max(12, enSize - 2))}><span style={{ fontSize: 10, fontWeight: 700 }}>A−</span></IconBtn>
              <IconBtn title="英文增大" onClick={() => setEnSize(Math.min(48, enSize + 2))}><span style={{ fontSize: 13, fontWeight: 700 }}>A+</span></IconBtn>
              <div className="sep" />
              <IconBtn title="中文减小" onClick={() => setZhSize(Math.max(12, zhSize - 2))}><span style={{ fontSize: 10, fontWeight: 700 }}>中−</span></IconBtn>
              <IconBtn title="中文增大" onClick={() => setZhSize(Math.min(48, zhSize + 2))}><span style={{ fontSize: 12, fontWeight: 700 }}>中+</span></IconBtn>
              <div className="sep" />
              <IconOpacity size={12} style={{ color: "rgba(255,255,255,0.6)", margin: "0 2px" }} />
              <div className="slider" style={{ width: 74, cursor: "pointer" }}
                   onClick={(e) => {
                     const r = e.currentTarget.getBoundingClientRect();
                     setOpacity(Math.round(Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * 100));
                   }}>
                <div className="fillp" style={{ width: opacity + "%" }} />
                <div className="knobp" style={{ left: opacity + "%" }} />
              </div>
              <div className="sep" />
              <IconBtn title="锁定 ⇧⌘L（穿透鼠标）" onClick={() => setLocked(true)}><IconLock size={12} /></IconBtn>
              <IconBtn title="关闭桌面歌词"><IconX size={12} /></IconBtn>
            </div>
          )}

          {/* 歌词本体：宽度改变 → 换行 → 高度自动撑开，顶部位置不跳动 */}
          <div className={"lyrics" + (locked || transparent ? "" : " edit-mode")}
               onDoubleClick={() => locked && setLocked(false)}
               style={{
                 position: "static", transform: "none", left: "auto",
                 width, maxWidth: "82%",
                 textAlign: "left",
                 cursor: locked ? "default" : "move",
                 background: transparent ? "transparent" : `rgba(0,0,0,${(0.5 * opacity / 100).toFixed(3)})`,
                 backdropFilter: transparent ? "none" : "blur(14px)",
                 WebkitBackdropFilter: transparent ? "none" : "blur(14px)",
                 borderRadius: 13,
                 outline: locked || transparent ? "none" : undefined,
               }}>
            <div className="l-en" lang="en" style={{
              fontSize: enSize, textAlign: "left",
              textShadow: "0 1px 12px rgba(0,0,0,0.65), 0 0 2px rgba(0,0,0,0.5)",
            }}>{cur.en}</div>
            <div className="l-zh" lang="zh" style={{
              fontSize: zhSize, textAlign: "left", marginTop: 8,
              color: "rgba(255,213,79,0.95)",
              textShadow: "0 1px 10px rgba(0,0,0,0.6)",
            }}>{cur.zh}</div>
          </div>
        </div>

        {locked && (
          <div className="lock-hint" style={{ left: 24, bottom: 24 }}>
            <IconLock size={13} style={{ color: "var(--accent-strong)" }} />
            <span lang="zh">已锁定 · 鼠标穿透，控制条与边框已隐藏 · 按</span>
            <kbd>⇧⌘L</kbd>
            <span lang="zh">或从「播放」菜单解锁</span>
          </div>
        )}
        {variant === "narrow" && !locked && (
          <div className="lock-hint" style={{ left: 24, bottom: 24 }}>
            <span lang="zh">宽度 340：换行后窗口自动增高（最小 320 × 100，最高 500）</span>
          </div>
        )}
      </div>
    );
  }

  Object.assign(window, { FloatingWindow, DesktopLyrics });
})();
