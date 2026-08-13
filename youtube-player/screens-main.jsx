/* screens-main.jsx — 主窗口全部画面：
   空状态 / 播放+双语 / 暂停跟随 / 翻译中 / 播放列表折叠 / 无字幕 / 禁止嵌入 */
(function () {
  const { useState, useEffect, useRef } = React;

  /* ---------------- 播放列表 ---------------- */
  function PlaylistItem({ v, active, onClick }) {
    return (
      <button className={"plist-item" + (active ? " active" : "")} onClick={onClick}>
        <div className="thumb" style={thumbStyle(v)}>
          <span className="dur">{v.duration}</span>
          {v.progress > 0 && <span className="prog" style={{ width: `${v.progress * 100}%` }} />}
        </div>
        <div className="plist-meta">
          <div className="plist-title">{v.title}</div>
          <div className="plist-sub">
            <span>{v.channel}</span>
            <Badge kind={v.status.kind} dot>{v.status.label}</Badge>
          </div>
        </div>
      </button>
    );
  }

  function Playlist({ collapsed, onToggle }) {
    if (collapsed) return null;
    return (
      <div className="plist">
        <div className="plist-head">
          <span>播放列表</span>
          <span style={{ fontWeight: 500 }}>{VIDEOS.length}</span>
        </div>
        <div className="plist-scroll">
          {VIDEOS.map((v) => <PlaylistItem key={v.id} v={v} active={v.current} />)}
        </div>
      </div>
    );
  }

  /* ---------------- 播放器 ---------------- */
  function Player({ time, playing, onTogglePlay }) {
    const total = 88;
    const pct = Math.min(100, (time / total) * 100);
    return (
      <div className="player">
        {/* 视频画面占位：真实产品为 YouTube 嵌入播放器 */}
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
      </div>
    );
  }

  /* 状态卡片：无字幕 / 禁止嵌入 */
  function PlayerStateCard({ kind }) {
    if (kind === "nosub") {
      return (
        <div className="statecard">
          <div className="ic-wrap"><IconCaptions size={22} /></div>
          <div className="st">这个视频没有可用字幕</div>
          <div className="sd" lang="zh">暂时无法生成双语字幕。可以稍后重新检测，或直接在 YouTube 中观看。</div>
          <div className="sa">
            <Btn primary><IconRefresh size={13} />重新检测</Btn>
            <Btn><IconYoutube size={13} />在 YouTube 打开</Btn>
            <Btn><IconTrash size={13} />从列表移除</Btn>
          </div>
        </div>
      );
    }
    return (
      <div className="statecard">
        <div className="ic-wrap"><IconAlert size={22} /></div>
        <div className="st">该视频不允许在第三方播放器中播放</div>
        <div className="sd" lang="zh">视频作者禁止了嵌入播放。字幕已获取成功，你仍然可以阅读，但外部播放暂不支持自动时间同步。</div>
        <div className="sa">
          <Btn primary><IconYoutube size={13} />在 YouTube 打开</Btn>
          <Btn>保留到播放列表</Btn>
          <Btn><IconTrash size={13} />从列表移除</Btn>
        </div>
      </div>
    );
  }

  /* 播放器下方操作区 */
  function VidBar({ floatOn, lyricOn, onFloat, onLyric, playing, onTogglePlay, onSkip }) {
    return (
      <div className="vidbar">
        <div className="vidbar-title">
          <div className="t">How to Speak So That People Want to Listen</div>
          <div className="c">TED · 218 万次观看</div>
        </div>
        <div className="transport">
          <IconBtn title="后退 5 秒" onClick={() => onSkip(-5)}><IconBack5 size={15} /></IconBtn>
          <IconBtn title={playing ? "暂停" : "播放"} onClick={onTogglePlay}>
            {playing ? <IconPause size={16} /> : <IconPlay size={16} />}
          </IconBtn>
          <IconBtn title="前进 5 秒" onClick={() => onSkip(5)}><IconFwd5 size={15} /></IconBtn>
        </div>
        <Btn toggled={floatOn} onClick={onFloat}><IconFloatWin size={13} />悬浮字幕</Btn>
        <Btn toggled={lyricOn} onClick={onLyric}><IconLyrics size={13} />桌面歌词</Btn>
        <IconBtn title="在 YouTube 打开"><IconExternal size={14} /></IconBtn>
      </div>
    );
  }

  /* ---------------- 字幕面板 ---------------- */
  function SubRow({ row, current, mode, onSeek }) {
    return (
      <button className={"sub-row" + (current ? " current" : "")} onClick={() => onSeek(row.start)}>
        <span className="sub-ts">{fmtTime(row.start)}</span>
        <span className="sub-text">
          {mode !== "zh" && <span className="sub-en" lang="en">{row.en}</span>}
          {mode !== "en" && (
            row.zh
              ? <span className="sub-zh" lang="zh">{row.zh}</span>
              : <span className="sub-zh-pending" />
          )}
        </span>
      </button>
    );
  }

  function SubtitlePanel({ mode, setMode, rows, currentId, follow, setFollow, onSeek, translating }) {
    const scrollRef = useRef(null);
    const curRef = useRef(null);

    useEffect(() => {
      if (follow && curRef.current) {
        curRef.current.scrollIntoView({ block: "center", behavior: "smooth" });
      }
    }, [currentId, follow]);

    const onWheel = () => { if (follow) setFollow(false); };

    return (
      <div className="subpanel">
        <div className="subpanel-head">
          <span className="h">字幕</span>
          <Seg
            options={[{ value: "en", label: "原文" }, { value: "zh", label: "中文" }, { value: "both", label: "双语" }]}
            value={mode} onChange={setMode}
          />
          <div style={{ flex: 1 }} />
          <IconBtn title={follow ? "自动跟随中" : "恢复自动跟随"} on={follow} onClick={() => setFollow(!follow)}>
            <IconFollow size={14} />
          </IconBtn>
          <IconBtn title="更多：重新翻译 / 复制全文 / 导出字幕"><IconMore size={14} /></IconBtn>
        </div>
        <div className="sub-scroll" ref={scrollRef} onWheel={onWheel}>
          {rows.map((r) => (
            <div key={r.id} ref={r.id === currentId ? curRef : null}>
              <SubRow row={r} current={r.id === currentId} mode={mode} onSeek={onSeek} />
            </div>
          ))}
          {!follow && (
            <button className="backtocur" onClick={() => setFollow(true)}>
              <IconFollow size={12} />回到当前字幕
            </button>
          )}
        </div>
        {translating && (
          <div className="subpanel-foot">
            <IconTranslate size={12} style={{ color: "var(--accent-strong)" }} />
            <span lang="zh">正在翻译 34 / 48 句</span>
            <div className="progressline"><div style={{ width: "70%" }} /></div>
          </div>
        )}
      </div>
    );
  }

  /* ---------------- 主窗口 ---------------- */
  function MainWindow({ player, variant }) {
    // variant: "playing" | "paused-follow" | "translating" | "collapsed" | "nosub" | "blocked"
    const [mode, setMode] = useState("both");
    const [follow, setFollow] = useState(variant !== "paused-follow");
    const [collapsed, setCollapsed] = useState(variant === "collapsed");
    const [floatOn, setFloatOn] = useState(false);
    const [lyricOn, setLyricOn] = useState(false);
    const translating = variant === "translating";
    const rows = translating ? subtitlesTranslating() : SUBTITLES;

    const cur = currentSubtitleAt(player.time);
    const seek = (t) => player.setTime(Math.max(0, t));
    const skip = (d) => player.setTime(Math.max(0, player.time + d));

    const titleRight = (
      <React.Fragment>
        <LinkField compact />
        <Btn primary style={{ height: 28 }}><IconPlus size={12} />添加</Btn>
        <IconBtn title="设置"><IconGear size={15} /></IconBtn>
      </React.Fragment>
    );

    return (
      <Window width={1180} height={720} titleRight={titleRight}>
        <div className="mainwin-body">
          <Playlist collapsed={collapsed} />
          <div className="center-col">
            <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", minHeight: 0 }}>
              <div className="player-wrap">
                {variant === "nosub" || variant === "blocked"
                  ? <PlayerStateCard kind={variant} />
                  : <Player time={player.time} playing={player.playing} onTogglePlay={player.toggle} />}
              </div>
              <VidBar
                floatOn={floatOn} lyricOn={lyricOn}
                onFloat={() => setFloatOn(!floatOn)} onLyric={() => setLyricOn(!lyricOn)}
                playing={player.playing} onTogglePlay={player.toggle} onSkip={skip}
              />
            </div>
            <div style={{ padding: "10px 16px", display: "flex", gap: 8, alignItems: "center" }}>
              <IconBtn title={collapsed ? "展开播放列表" : "折叠播放列表"} on={!collapsed} onClick={() => setCollapsed(!collapsed)}>
                <IconSidebar size={15} />
              </IconBtn>
              <span style={{ fontSize: 11, color: "var(--text-3)" }} lang="zh">
                {collapsed ? "播放列表已折叠" : "分栏宽度可拖动调整并记忆"}
              </span>
            </div>
          </div>
          <SubtitlePanel
            mode={mode} setMode={setMode}
            rows={rows} currentId={cur.id}
            follow={follow} setFollow={setFollow}
            onSeek={seek} translating={translating}
          />
        </div>
      </Window>
    );
  }

  /* ---------------- 空状态 ---------------- */
  function MainEmpty() {
    const [link, setLink] = useState("");
    const [err, setErr] = useState(false);
    const submit = () => {
      const ok = /^(https?:\/\/)?(www\.)?(youtube\.com\/(watch|shorts|embed)|youtu\.be\/)/.test(link.trim());
      setErr(!ok);
    };
    return (
      <Window width={1180} height={720} titleRight={
        <IconBtn title="设置"><IconGear size={15} /></IconBtn>
      }>
        <div className="empty-wrap">
          <div className="empty-inner">
            <div className="empty-logo"><IconCaptions size={30} style={{ color: "var(--accent-strong)" }} /></div>
            <div>
              <div className="empty-title">EchoSub</div>
              <div className="empty-sub" lang="zh" style={{ marginTop: 6 }}>
                粘贴一个 YouTube 链接开始。无需登录，公开视频即可生成时间对齐的双语字幕。
              </div>
            </div>
            <div style={{ width: "100%", display: "flex", flexDirection: "column", gap: 6 }}>
              <div className="empty-input">
                <LinkField value={link} onChange={(v) => { setLink(v); setErr(false); }} />
                <Btn primary onClick={submit}>添加并播放</Btn>
              </div>
              {err && (
                <div className="err-line" lang="zh">
                  <IconAlert size={12} />无法识别的链接，支持 youtube.com/watch、youtu.be、shorts 和 embed 链接。
                </div>
              )}
            </div>
            <div className="empty-feats">
              <div className="feat">
                <span className="fi"><IconTranslate size={16} /></span>
                <div className="ft" lang="zh">双语字幕</div>
                <div className="fd" lang="zh">英文原文与简体中文逐句对齐，按完整语义分句，适合阅读和跟读。</div>
              </div>
              <div className="feat">
                <span className="fi"><IconFollow size={16} /></span>
                <div className="ft" lang="zh">逐句跳转</div>
                <div className="fd" lang="zh">点击任意一句回到对应时间，没听懂就反复收听这一句。</div>
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
