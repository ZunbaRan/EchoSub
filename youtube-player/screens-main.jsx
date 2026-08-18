/* screens-main.jsx — 主窗口 v0.1.2：
   URL 栏 / 播放列表（隐藏·删除·右键·多任务）/ 循环 / 窗口内全屏 /
   分栏折叠与拖动 / 字幕面板任务状态机 / 更多菜单与确认 / 背景卡浮层 */
(function () {
  const { useState, useEffect, useRef, useCallback } = React;

  /* ================= 通用：右键菜单 & sheet ================= */
  function CtxMenu({ x, y, onClose, children, style }) {
    const ref = useRef(null);
    useEffect(() => {
      const h = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
      document.addEventListener("mousedown", h);
      return () => document.removeEventListener("mousedown", h);
    }, [onClose]);
    return <div className="ctxmenu" ref={ref} style={{ left: x, top: y, ...style }}>{children}</div>;
  }

  function Sheet({ children, onClose }) {
    return (
      <div className="sheet-overlay" onClick={onClose}>
        <div className="sheet" onClick={(e) => e.stopPropagation()}>{children}</div>
      </div>
    );
  }

  /* ================= 顶部 URL 区 ================= */
  function URLToolbar() {
    const [link, setLink] = useState("");
    const [err, setErr] = useState(false);
    const submit = () => {
      if (!link.trim()) return;
      const ok = /^(https?:\/\/)?(www\.)?(youtube\.com\/(watch|shorts|embed)|youtu\.be\/)/.test(link.trim());
      setErr(!ok);
    };
    return (
      <React.Fragment>
        <div className={"field" + (err ? " focused" : "")} style={{ width: 320, borderColor: err ? "var(--red)" : undefined }}>
          <IconLink size={13} />
          <input
            placeholder="粘贴 YouTube 链接开始…"
            value={link}
            onChange={(e) => { setLink(e.target.value); setErr(false); }}
            onKeyDown={(e) => e.key === "Enter" && submit()}
          />
          <IconBtn title="从剪贴板粘贴" onClick={() => setLink("https://www.youtube.com/watch?v=dQw4w9WgXcQ")}>
            <IconClipboard size={13} />
          </IconBtn>
        </div>
        <Btn primary style={{ width: 76, height: 28 }} onClick={submit}><IconPlus size={12} />添加</Btn>
        <IconBtn title="设置 ⌘,"><IconGear size={15} /></IconBtn>
        {err && (
          <div style={{
            position: "absolute", top: 50, right: 110, zIndex: 55,
            background: "rgba(44,44,50,0.97)", borderRadius: 8, padding: "7px 11px",
            fontSize: 11, color: "var(--red)", display: "flex", alignItems: "center", gap: 6,
            boxShadow: "var(--shadow-pop), inset 0 0 0 0.5px rgba(255,255,255,0.12)",
          }}>
            <IconAlert size={12} /><span lang="zh">无法识别这个 YouTube 链接</span>
          </div>
        )}
      </React.Fragment>
    );
  }

  /* ================= 播放列表 ================= */
  const STATUS_COLOR = { mute: "rgba(255,255,255,0.35)", busy: "#409cff", ok: "#30d158", warn: "#ff9f0a", err: "#ff453a" };

  function PlaylistItem({ v, active, onCtx }) {
    const st = STATUS[v.status];
    return (
      <button className={"plist-item" + (active ? " active" : "")}
              onContextMenu={(e) => { e.preventDefault(); onCtx(e, v); }}>
        <div className="thumb" style={thumbStyle(v)}>
          <span className="dur">{v.duration}</span>
          {v.progress > 0 && <span className="prog" style={{ width: `${v.progress * 100}%` }} />}
        </div>
        <div className="plist-meta">
          <div className="plist-title">{v.title}</div>
          <div className="plist-sub">
            <span>{v.channel}</span>
          </div>
          <div className="plist-status">
            <span className="status-dot" style={{ background: STATUS_COLOR[st.kind] }} />
            <span className="lbl" style={{ color: STATUS_COLOR[st.kind] }} lang="zh">{st.label}</span>
          </div>
        </div>
      </button>
    );
  }

  function Playlist({ view, setView, onDelete, initialMenu }) {
    const [ctx, setCtx] = useState(initialMenu || null); // {x,y,v,hidden}
    const items = view === "hidden" ? HIDDEN_VIDEOS : VIDEOS;
    const openCtx = (e, v) => {
      const host = e.currentTarget.closest(".plist").getBoundingClientRect();
      setCtx({ x: e.clientX - host.left, y: e.clientY - host.top, v, hidden: view === "hidden" });
    };
    return (
      <div className="plist" style={{ position: "relative" }}>
        <div className="plist-head">
          {view === "hidden" ? (
            <React.Fragment>
              <span lang="zh">已隐藏</span>
              <button className="ctx-item" style={{ padding: "2px 8px", fontSize: 10.5 }} onClick={() => setView("active")} lang="zh">返回</button>
            </React.Fragment>
          ) : (
            <React.Fragment>
              <span lang="zh">播放列表</span>
              <span style={{ fontWeight: 500 }}>{VIDEOS.length}</span>
            </React.Fragment>
          )}
        </div>
        {view === "active" && HIDDEN_VIDEOS.length > 0 && (
          <button className="hidden-entry" onClick={() => setView("hidden")}>
            <IconEyeOff size={12} /><span lang="zh">已隐藏 {HIDDEN_VIDEOS.length}</span>
            <span style={{ flex: 1 }} /><IconChevronD size={10} style={{ transform: "rotate(-90deg)", opacity: 0.4 }} />
          </button>
        )}
        <div className="plist-scroll">
          {items.map((v) => <PlaylistItem key={v.id} v={v} active={v.current && view === "active"} onCtx={openCtx} />)}
        </div>
        {ctx && (
          <CtxMenu x={ctx.x} y={ctx.y} onClose={() => setCtx(null)}>
            {ctx.hidden ? (
              <React.Fragment>
                <button className="ctx-item" onClick={() => setCtx(null)}><span lang="zh">恢复到播放列表</span><IconRestore size={12} /></button>
                <div className="ctx-sep" />
                <button className="ctx-item danger" onClick={() => { setCtx(null); onDelete(ctx.v); }}><span lang="zh">删除…</span></button>
              </React.Fragment>
            ) : (
              <React.Fragment>
                <button className="ctx-item" onClick={() => setCtx(null)}><span lang="zh">隐藏</span><IconEyeOff size={12} /></button>
                <div className="ctx-sep" />
                <button className="ctx-item danger" onClick={() => { setCtx(null); onDelete(ctx.v); }}><span lang="zh">删除…</span></button>
              </React.Fragment>
            )}
          </CtxMenu>
        )}
      </div>
    );
  }

  /* ================= 播放器 ================= */
  function Player({ time, playing, onTogglePlay, chrome }) {
    const total = 88;
    const pct = Math.min(100, (time / total) * 100);
    return (
      <div className="player">
        <div style={{
          position: "absolute", inset: 0,
          background:
            "radial-gradient(70% 90% at 30% 20%, rgba(60,90,160,0.35), transparent 60%)," +
            "radial-gradient(60% 80% at 80% 75%, rgba(150,60,90,0.28), transparent 60%)," +
            "linear-gradient(160deg, #14161c, #0a0a0d)",
        }} />
        <div style={{
          position: "absolute", inset: 0, display: "flex", flexDirection: "column",
          alignItems: "center", justifyContent: "center", gap: 10,
        }}>
          <button onClick={onTogglePlay} style={{
            width: 56, height: 56, borderRadius: "50%", border: "none", cursor: "pointer",
            background: "rgba(255,255,255,0.14)", backdropFilter: "blur(8px)",
            color: "#fff", display: "flex", alignItems: "center", justifyContent: "center",
          }}>
            {playing ? <IconPause size={22} /> : <IconPlay size={22} />}
          </button>
          <div style={{ fontSize: 11, color: "rgba(255,255,255,0.55)", letterSpacing: 0.4 }}>
            YouTube 嵌入播放器 · 09:58
          </div>
        </div>
        <div className="yt-badge">YouTube</div>
        {chrome !== false && (
          <div className="player-ctrl">
            <span className="ic" onClick={onTogglePlay} style={{ cursor: "pointer" }}>
              {playing ? <IconPause size={15} /> : <IconPlay size={15} />}
            </span>
            <div className="player-track">
              <div className="buf" style={{ width: "68%" }} />
              <div className="played" style={{ width: pct + "%" }} />
              <div className="knob" style={{ left: pct + "%" }} />
            </div>
            <span className="player-time">{fmtTime(time)} / 1:28</span>
          </div>
        )}
      </div>
    );
  }

  function PlayerStateCard({ kind }) {
    if (kind === "noSubtitles") {
      return (
        <div className="statecard">
          <div className="ic-wrap"><IconCaptions size={22} /></div>
          <div className="st" lang="zh">这个视频没有可用字幕</div>
          <div className="sd" lang="zh">暂时无法生成双语字幕。可以稍后重新检测，或直接在 YouTube 中观看。</div>
          <div className="sa">
            <Btn primary><IconRefresh size={13} />重新检测</Btn>
            <Btn><IconYoutube size={13} />在 YouTube 打开</Btn>
          </div>
        </div>
      );
    }
    return (
      <div className="statecard">
        <div className="ic-wrap"><IconAlert size={22} /></div>
        <div className="st" lang="zh">该视频不允许在第三方播放器中播放</div>
        <div className="sd" lang="zh">可以在 YouTube 中打开；已获取的字幕仍可继续阅读。</div>
        <div className="sa">
          <Btn primary><IconYoutube size={13} />在 YouTube 打开</Btn>
        </div>
      </div>
    );
  }

  /* ================= 播放器下方控制条 ================= */
  const LOOP_STATES = [
    { id: "none", icon: IconRepeat, on: false, tip: "循环：关闭" },
    { id: "list", icon: IconRepeat, on: true, tip: "循环：列表循环" },
    { id: "single", icon: IconRepeat1, on: true, tip: "循环：单首循环" },
  ];

  function VidBar({ player, loop, setLoop, onFocus }) {
    const L = LOOP_STATES[loop];
    const LoopIcon = L.icon;
    return (
      <div className="vidbar">
        <div className="vidbar-title">
          <div className="t">How to Speak So That People Want to Listen</div>
          <div className="c">TED · 9:58</div>
        </div>
        <div className="transport">
          <IconBtn title="后退 5 秒" onClick={() => player.setTime(Math.max(0, player.time - 5))}><IconBack5 size={15} /></IconBtn>
          <IconBtn title={player.playing ? "暂停" : "播放"} onClick={player.toggle}>
            {player.playing ? <IconPause size={16} /> : <IconPlay size={16} />}
          </IconBtn>
          <IconBtn title="前进 5 秒" onClick={() => player.setTime(player.time + 5)}><IconFwd5 size={15} /></IconBtn>
        </div>
        <IconBtn title={L.tip} on={L.on} onClick={() => setLoop((loop + 1) % 3)}><LoopIcon size={14} /></IconBtn>
        <IconBtn title="悬浮字幕 ⇧⌘F"><IconFloatWin size={14} /></IconBtn>
        <IconBtn title="桌面歌词 ⇧⌘D"><IconLyrics size={14} /></IconBtn>
        <IconBtn title="播放器窗口全屏（窗口内，Esc 退出）" onClick={onFocus}><IconExpand size={14} /></IconBtn>
        <IconBtn title="在 YouTube 打开"><IconExternal size={14} /></IconBtn>
      </div>
    );
  }

  /* ================= 字幕面板 ================= */
  function SubRow({ row, current, mode, onSeek, onCtx, gloss, onGlossOpen, onGlossRemove,
                   demo, editing, editedZh, onSaveZh, onCancelEdit }) {
    // 选词演示：s13 中的 onwards 渲染为选中态
    const renderEn = () => {
      if ((demo === "lookup-toolbar" || demo === "lookup-popover") && row.id === "s13") {
        return (
          <span className="sub-en" lang="en">
            From that day <span className="hl-select">onwards</span>, I decided to speak differently.
          </span>
        );
      }
      return <span className="sub-en" lang="en">{row.en}</span>;
    };
    const zhText = (editedZh && editedZh[row.id]) || row.zh;
    const isEdited = editedZh && !!editedZh[row.id];
    return (
      <div className={"sub-row" + (current ? " current" : "")} role="button" tabIndex={0}
              onClick={() => onSeek(row.start)}
              onContextMenu={(e) => onCtx(e, row)}>
        <span className="sub-ts">{fmtTime(row.start)}</span>
        <span className="sub-text">
          {mode !== "zh" && renderEn()}
          {mode !== "en" && (
            editing ? (
              <EditZhBlock row={{ ...row, zh: zhText }} onSave={onSaveZh} onCancel={onCancelEdit} />
            ) : zhText
              ? <span className="sub-zh" lang="zh">
                  {zhText}
                  {isEdited && <span className="edited-tag" lang="zh">已编辑</span>}
                </span>
              : <span className="zh-missing" lang="zh">
                  待补全
                  <span className="retry" onClick={(e) => e.stopPropagation()}>
                    <IconRefresh size={10} />补翻此句
                  </span>
                </span>
          )}
          <GlossEntries entries={gloss} onOpen={onGlossOpen} onRemove={onGlossRemove} />
        </span>
      </div>
    );
  }

  function SubtitlePanel({ mode, setMode, phase, rows, currentId, follow, setFollow, onSeek,
                           bgCard, setBgCard, initialMore, initialRowMenu, onRetranslateAll, demo }) {
    const scrollRef = useRef(null);
    const curRef = useRef(null);
    const [moreOpen, setMoreOpen] = useState(!!initialMore);
    const [rowMenu, setRowMenu] = useState(initialRowMenu || null); // {x,y,row}
    const hostRef = useRef(null);
    const [gloss, setGloss] = useState(GLOSS_MAP);
    const [vocabOpen, setVocabOpen] = useState(demo === "vocab");
    const [popoverOpen, setPopoverOpen] = useState(demo === "lookup-popover");
    const [editingRow, setEditingRow] = useState(demo === "edit-zh" ? "s05" : null);
    const [editedZh, setEditedZh] = useState(
      demo === "edit-zh" ? { s04: "然而很多人都有这样的体会：自己说话时，别人并没有在听。" } : {}
    );

    useEffect(() => {
      if (follow && curRef.current) {
        curRef.current.scrollIntoView({ block: "center", behavior: "smooth" });
      }
    }, [currentId, follow]);

    const openRowMenu = (e, row) => {
      e.preventDefault();
      const host = hostRef.current.getBoundingClientRect();
      setRowMenu({ x: e.clientX - host.left, y: e.clientY - host.top, row });
    };

    const footer = PHASE_FOOTER[phase];
    const bgState = phase === "noSubtitles" || phase === "failed" ? "disabled"
      : bgCard.phase === "generating" ? "working"
      : bgCard.phase === "error" ? "warn" : "default";
    const glossCount = Object.values(gloss).reduce((n, arr) => n + arr.length, 0);

    return (
      <div className="subpanel" ref={hostRef} style={{ position: "relative" }}>
        <div className="subpanel-head">
          <span className="h" lang="zh">字幕</span>
          <Seg
            options={[{ value: "en", label: "原文" }, { value: "zh", label: "中文" }, { value: "both", label: "双语" }]}
            value={mode} onChange={setMode}
          />
          <div style={{ flex: 1 }} />
          <IconBtn title={"本片词汇（" + glossCount + "）"} on={vocabOpen} onClick={() => setVocabOpen(!vocabOpen)}>
            <IconDocText size={14} />
          </IconBtn>
          <IconBtn
            title={bgState === "disabled" ? "背景卡（无字幕时不可用）" : "视频背景卡"}
            disabled={bgState === "disabled"}
            className={"iconbtn" + (bgState === "working" ? " working" : bgState === "warn" ? " warnstate" : "")}
            onClick={() => bgState !== "disabled" && setBgCard({ ...bgCard, visible: !bgCard.visible })}
          >
            <IconSparkle size={14} />
          </IconBtn>
          <IconBtn title={follow ? "自动跟随中" : "恢复自动跟随"} on={follow} onClick={() => setFollow(!follow)}>
            <IconFollow size={14} />
          </IconBtn>
          <IconBtn title="更多" onClick={() => setMoreOpen(!moreOpen)}><IconMore size={14} /></IconBtn>
        </div>

        {moreOpen && (
          <CtxMenu x={220} y={38} onClose={() => setMoreOpen(false)} style={{ right: 8, left: "auto" }}>
            <button className="ctx-item" onClick={() => setMoreOpen(false)}><span lang="zh">补全翻译（12 句）</span></button>
            <button className="ctx-item" onClick={() => { setMoreOpen(false); onRetranslateAll(); }}><span lang="zh">全部重新翻译…</span></button>
            <div className="ctx-sep" />
            <button className="ctx-item" onClick={() => setMoreOpen(false)}><span lang="zh">重新获取原字幕</span></button>
          </CtxMenu>
        )}

        <div className="sub-scroll" ref={scrollRef} onWheel={() => follow && setFollow(false)}>
          {rows.map((r) => (
            <div key={r.id} ref={r.id === currentId ? curRef : null} style={{ position: "relative" }}>
              <SubRow
                row={r} current={r.id === currentId} mode={mode} onSeek={onSeek} onCtx={openRowMenu}
                gloss={gloss[r.id]}
                onGlossOpen={() => setPopoverOpen(true)}
                onGlossRemove={(g) => setGloss({ ...gloss, [r.id]: gloss[r.id].filter((x) => x.id !== g.id) })}
                demo={demo}
                editing={editingRow === r.id}
                editedZh={editedZh}
                onSaveZh={(text) => { setEditedZh({ ...editedZh, [r.id]: text }); setEditingRow(null); }}
                onCancelEdit={() => setEditingRow(null)}
              />
              {(demo === "lookup-toolbar" || (demo === "lookup-popover" && popoverOpen)) && r.id === "s13" && (
                <SelectionToolbar
                  style={{ top: -32, left: 88 }}
                  onDirect={() => {}}
                  onDetail={() => setPopoverOpen(true)}
                />
              )}
            </div>
          ))}
          {!follow && (
            <button className="backtocur" onClick={() => setFollow(true)}>
              <IconFollow size={12} />回到当前字幕
            </button>
          )}
        </div>

        <div className="subpanel-foot">
          {footer.spinner && <span className="spinner" />}
          <span lang="zh" style={footer.error ? { color: "var(--red)" } : footer.warn ? { color: "var(--orange)" } : undefined}>
            {footer.text}
          </span>
          {footer.progress != null && <div className="progressline"><div style={{ width: `${footer.progress * 100}%` }} /></div>}
        </div>

        {rowMenu && (
          <CtxMenu x={rowMenu.x} y={rowMenu.y} onClose={() => setRowMenu(null)}>
            <button className="ctx-item" onClick={() => setRowMenu(null)}><span lang="zh">{rowMenu.row.zh ? "重新翻译此句" : "补翻此句"}</span></button>
            <button className="ctx-item" onClick={() => { setEditingRow(rowMenu.row.id); setRowMenu(null); }}><span lang="zh">编辑译文</span></button>
          </CtxMenu>
        )}

        {demo === "lookup-popover" && popoverOpen && (
          <VocabPopover
            style={{ left: -358, top: 96 }}
            onClose={() => setPopoverOpen(false)}
            onSeekSentence={() => onSeek(84)}
          />
        )}

        {vocabOpen && (
          <VocabPanel
            onClose={() => setVocabOpen(false)}
            onSeek={onSeek}
            onOpen={() => { setVocabOpen(false); setPopoverOpen(true); }}
          />
        )}

        {bgCard.visible && (
          <BackgroundCard
            phase={bgCard.phase}
            onClose={() => setBgCard({ ...bgCard, visible: false })}
            onSeek={onSeek}
            onPhaseChange={(p) => setBgCard({ ...bgCard, phase: p })}
          />
        )}
      </div>
    );
  }

  /* ================= 分栏分隔线（可拖动） ================= */
  function Divider({ onDrag }) {
    const [drag, setDrag] = useState(false);
    const onDown = (e) => {
      e.preventDefault();
      setDrag(true);
      const startX = e.clientX;
      const move = (ev) => onDrag(ev.clientX - startX, false);
      const up = () => { setDrag(false); document.removeEventListener("mousemove", move); document.removeEventListener("mouseup", up); };
      document.addEventListener("mousemove", move);
      document.addEventListener("mouseup", up);
    };
    return <div className={"divider" + (drag ? " dragging" : "")} onMouseDown={onDown} />;
  }

  /* ================= 主窗口 ================= */
  function MainWindow({ player, variant = "playing", width = 1180, height = 720 }) {
    // variant: playing | phases（外部控制 phase）| left-collapsed | right-collapsed | both-collapsed |
    //          focus | playlist-menu | hidden | delete-sheet | more-menu | partial | blocked | bgcard-* |
    //          lookup-toolbar | gloss | lookup-popover | vocab | edit-zh
    const [mode, setMode] = useState("both");
    const [follow, setFollow] = useState(true);
    const [leftW, setLeftW] = useState(236);
    const [rightW, setRightW] = useState(348);
    const [leftCol, setLeftCol] = useState(variant === "left-collapsed" || variant === "both-collapsed");
    const [rightCol, setRightCol] = useState(variant === "right-collapsed" || variant === "both-collapsed");
    const [loop, setLoop] = useState(0);
    const [focus, setFocus] = useState(variant === "focus");
    const [listView, setListView] = useState(variant === "hidden" ? "hidden" : "active");
    const [phase, setPhase] = useState(
      variant === "partial" ? "partial" : variant === "phases" ? "translating" : "ready"
    );
    const [bgCard, setBgCard] = useState(() => {
      if (variant.startsWith("bgcard-")) {
        return { visible: true, phase: variant.replace("bgcard-", "") };
      }
      return { visible: false, phase: "ready" };
    });
    const [deleteV, setDeleteV] = useState(variant === "delete-sheet" ? VIDEOS[1] : null);
    const [retransAll, setRetransAll] = useState(false);

    // phases 展示模式：外部通过 window.__setPhase 控制（由 app.jsx 的开关驱动）
    useEffect(() => {
      if (variant === "phases") {
        window.__mainSetPhase = setPhase;
        return () => { delete window.__mainSetPhase; };
      }
    }, [variant]);

    useEffect(() => {
      if (!focus) return;
      const h = (e) => e.key === "Escape" && setFocus(false);
      document.addEventListener("keydown", h);
      return () => document.removeEventListener("keydown", h);
    }, [focus]);

    const cur = currentSubtitleAt(player.time);
    const rows = phase === "partial" ? subtitlesPartial() : SUBTITLES;
    const seek = (t) => player.setTime(Math.max(0, t));

    const effectivePhase = variant === "blocked" ? "ready" : phase;

    return (
      <Window width={width} height={height} titleRight={<URLToolbar />}>
        <div className="mainwin-body">
          {!leftCol && (
            <React.Fragment>
              <div style={{ width: leftW, flexShrink: 0, display: "flex", minHeight: 0 }}>
                <Playlist
                  view={listView} setView={setListView}
                  onDelete={(v) => setDeleteV(v)}
                  initialMenu={variant === "playlist-menu" ? { x: 26, y: 100, v: VIDEOS[1], hidden: false } : null}
                />
              </div>
              <Divider onDrag={(dx) => setLeftW((w) => Math.min(360, Math.max(180, w + dx)))} />
            </React.Fragment>
          )}

          <div className="center-col">
            <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", minHeight: 0 }}>
              <div className="player-wrap" style={{ paddingTop: 20 }}>
                {variant === "blocked" || effectivePhase === "noSubtitles"
                  ? <PlayerStateCard kind={variant === "blocked" ? "blocked" : "noSubtitles"} />
                  : <Player time={player.time} playing={player.playing} onTogglePlay={player.toggle} />}
              </div>
              <VidBar player={player} loop={loop} setLoop={setLoop} onFocus={() => setFocus(true)} />
            </div>
            <div style={{ padding: "8px 12px", display: "flex", gap: 4, alignItems: "center" }}>
              <IconBtn title={leftCol ? "展开播放列表" : "折叠播放列表"} on={!leftCol} onClick={() => setLeftCol(!leftCol)}>
                <IconSidebar size={15} />
              </IconBtn>
              <div style={{ flex: 1 }} />
              <IconBtn title={rightCol ? "展开字幕面板" : "折叠字幕面板"} on={!rightCol}
                       onClick={() => setRightCol(!rightCol)}>
                <IconCaptions size={15} />
              </IconBtn>
            </div>
          </div>

          {!rightCol && (
            <React.Fragment>
              <Divider onDrag={(dx) => setRightW((w) => Math.min(520, Math.max(280, w - dx)))} />
              <div style={{ width: rightW, flexShrink: 0, display: "flex", minHeight: 0 }}>
                <SubtitlePanel
                  mode={mode} setMode={setMode}
                  phase={effectivePhase} rows={rows} currentId={cur.id}
                  follow={follow} setFollow={setFollow} onSeek={seek}
                  bgCard={bgCard} setBgCard={setBgCard}
                  initialMore={variant === "more-menu"}
                  initialRowMenu={variant === "partial" ? { x: 120, y: 210, row: rows[2] } : null}
                  onRetranslateAll={() => setRetransAll(true)}
                  demo={["lookup-toolbar", "gloss", "lookup-popover", "vocab", "edit-zh"].includes(variant) ? variant : null}
                />
              </div>
            </React.Fragment>
          )}
        </div>

        {/* 播放器窗口内全屏：不进入系统全屏，仅覆盖当前窗口内容 */}
        {focus && (
          <div className="focus-overlay">
            <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", padding: "4vh 4vw" }}>
              <div style={{ width: "min(100%, calc((100vh - 8vh) * 16 / 9))" }}>
                <Player time={player.time} playing={player.playing} onTogglePlay={player.toggle} />
              </div>
            </div>
            <button className="exit-focus" title="退出（Esc）" onClick={() => setFocus(false)}>
              <IconX size={18} />
            </button>
          </div>
        )}

        {/* 永久删除确认 */}
        {deleteV && (
          <Sheet onClose={() => setDeleteV(null)}>
            <div className="sh-t"><IconTrash size={15} style={{ color: "var(--red)" }} /><span lang="zh">永久删除这个视频？</span></div>
            <div className="sh-d" lang="zh">「{deleteV.title}」将从资料库中彻底移除。与「隐藏」不同，此操作不可撤销，将删除：</div>
            <div className="sh-list" lang="zh">
              视频信息<br />原字幕<br />翻译结果<br />视频背景卡
            </div>
            <div className="sh-a">
              <Btn onClick={() => setDeleteV(null)} lang="zh">取消</Btn>
              <Btn className="btn danger" onClick={() => setDeleteV(null)} lang="zh">永久删除</Btn>
            </div>
          </Sheet>
        )}

        {/* 全部重新翻译确认 */}
        {retransAll && (
          <Sheet onClose={() => setRetransAll(false)}>
            <div className="sh-t"><IconTranslate size={15} style={{ color: "var(--accent-strong)" }} /><span lang="zh">全部重新翻译？</span></div>
            <div className="sh-d" lang="zh">将清空这个视频的全部中文翻译并重新开始。英文原字幕不受影响，视频背景卡保持不变。</div>
            <div className="sh-a">
              <Btn onClick={() => setRetransAll(false)} lang="zh">取消</Btn>
              <Btn primary onClick={() => { setRetransAll(false); setPhase("translating"); }} lang="zh">全部重新翻译</Btn>
            </div>
          </Sheet>
        )}
      </Window>
    );
  }

  /* ================= 空状态 ================= */
  function MainEmpty() {
    return (
      <Window width={1180} height={720} titleRight={<URLToolbar />}>
        <div className="empty-wrap">
          <div className="empty-inner">
            <div className="empty-logo"><IconCaptions size={30} style={{ color: "var(--accent-strong)" }} /></div>
            <div>
              <div className="empty-title">EchoSub</div>
              <div className="empty-sub" lang="zh" style={{ marginTop: 6 }}>
                粘贴一个 YouTube 链接开始
              </div>
            </div>
            <div className="empty-feats">
              <div className="feat">
                <span className="fi"><IconTranslate size={16} /></span>
                <div className="ft" lang="zh">双语字幕</div>
                <div className="fd" lang="zh">英文原文与简体中文逐句对齐，按完整语义分句，适合阅读和跟读。</div>
              </div>
              <div className="feat">
                <span className="fi"><IconSparkle size={16} /></span>
                <div className="ft" lang="zh">视频背景卡</div>
                <div className="fd" lang="zh">翻译前先读懂全文，长视频的人名与术语更一致。</div>
              </div>
              <div className="feat">
                <span className="fi"><IconLyrics size={16} /></span>
                <div className="ft" lang="zh">桌面歌词</div>
                <div className="fd" lang="zh">字幕悬浮在所有窗口之上，边看视频边记笔记。</div>
              </div>
            </div>
          </div>
        </div>
      </Window>
    );
  }

  Object.assign(window, { MainWindow, MainEmpty });
})();
