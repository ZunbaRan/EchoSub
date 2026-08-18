/* app.jsx — 设计稿舞台 v0.1.2：画面索引、深浅色切换、播放模拟（状态持久化） */
(function () {
  const { useState, useEffect, useMemo } = React;

  const SCREENS = [
    { group: "主窗口", items: [
      { id: "empty",          label: "空状态 / 首次打开" },
      { id: "playing",        label: "默认三栏 · 长句双语字幕" },
      { id: "phases",         label: "字幕任务状态（页内切换）" },
      { id: "partial",        label: "待补全 · 单句右键重试" },
      { id: "more-menu",      label: "更多菜单 · 全部重新翻译" },
      { id: "playlist-menu",  label: "播放列表 · 右键菜单" },
      { id: "hidden",         label: "已隐藏列表与恢复" },
      { id: "delete-sheet",   label: "永久删除确认" },
      { id: "blocked",        label: "禁止嵌入 · 字幕可读" },
      { id: "left-collapsed", label: "左栏折叠" },
      { id: "right-collapsed",label: "右栏折叠" },
      { id: "both-collapsed", label: "左右均折叠（视频专注）" },
      { id: "focus",          label: "播放器窗口内全屏" },
    ]},
    { group: "选词讲解", items: [
      { id: "lookup-toolbar", label: "选中单词 · 快捷工具条" },
      { id: "gloss",          label: "词汇直译 · 内联注释" },
      { id: "lookup-popover", label: "词汇详解 · Popover" },
      { id: "vocab",          label: "本片词汇汇总" },
      { id: "edit-zh",        label: "编辑译文（仅中文）" },
      { id: "float-lookup",   label: "悬浮字幕 · 选词讲解" },
    ]},
    { group: "视频背景卡", items: [
      { id: "bgcard-empty",      label: "未生成" },
      { id: "bgcard-generating", label: "生成中" },
      { id: "bgcard-ready",      label: "完成（阅读模式）" },
      { id: "bgcard-editing",    label: "编辑模式" },
      { id: "bgcard-error",      label: "失败" },
    ]},
    { group: "字幕窗口", items: [
      { id: "float",             label: "悬浮字幕 · 默认（Pin + 透明度）" },
      { id: "float-narrow",      label: "悬浮字幕 · 窄窗长句换行" },
      { id: "float-transparent", label: "悬浮字幕 · 完全透明" },
      { id: "lyrics-edit",       label: "桌面歌词 · 编辑状态" },
      { id: "lyrics-locked",     label: "桌面歌词 · 锁定状态" },
      { id: "lyrics-narrow",     label: "桌面歌词 · 窄宽自动增高" },
      { id: "lyrics-transparent",label: "桌面歌词 · 全透明无底板" },
    ]},
    { group: "设置", items: [
      { id: "set-subs",    label: "字幕与语言" },
      { id: "set-sources", label: "字幕来源（新增）" },
      { id: "set-trans",   label: "翻译服务" },
      { id: "set-appear",  label: "外观（配色预设 · 独立字号）" },
      { id: "set-data",    label: "缓存与隐私" },
    ]},
    { group: "系统", items: [
      { id: "app-menu",   label: "App 菜单与诊断入口" },
      { id: "min-window", label: "最小窗口 900 × 600" },
    ]},
  ];
  const FLAT = SCREENS.flatMap((g) => g.items.map((it) => ({ ...it, group: g.group })));

  const ls = {
    get(k, d) { try { const v = localStorage.getItem("echosub-" + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("echosub-" + k, JSON.stringify(v)); } catch (e) {} },
  };

  // 画面超出舞台时等比缩小适配
  function FitView({ children, resetKey }) {
    const outerRef = React.useRef(null);
    const innerRef = React.useRef(null);
    const [scale, setScale] = useState(1);
    useEffect(() => {
      const measure = () => {
        const o = outerRef.current, i = innerRef.current;
        if (!o || !i) return;
        const pad = 80;
        setScale(Math.min(1, (o.clientWidth - pad) / i.offsetWidth, (o.clientHeight - pad) / i.offsetHeight));
      };
      measure();
      const t = setTimeout(measure, 60);
      const ro = new ResizeObserver(measure);
      if (outerRef.current) ro.observe(outerRef.current);
      return () => { clearTimeout(t); ro.disconnect(); };
    }, [resetKey]);
    return (
      <div ref={outerRef} style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", overflow: "hidden" }}>
        <div ref={innerRef} style={{ width: "max-content", height: "max-content", transform: `scale(${scale})`, transformOrigin: "center center", flexShrink: 0 }}>
          {children}
        </div>
      </div>
    );
  }

  // 字幕任务状态展示：页内切换 phase
  const PHASE_OPTIONS = [
    { value: "fetching", label: "获取字幕" },
    { value: "analyzing", label: "全文理解" },
    { value: "translating", label: "逐批翻译" },
    { value: "partial", label: "待补全" },
    { value: "failed", label: "失败" },
    { value: "noSubtitles", label: "无字幕" },
  ];
  function PhaseShowcase({ player }) {
    const [p, setP] = useState("translating");
    useEffect(() => {
      const t = setTimeout(() => window.__mainSetPhase && window.__mainSetPhase(p), 60);
      return () => clearTimeout(t);
    }, [p]);
    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
        <div data-theme="dark" style={{
          display: "flex", gap: 2, background: "rgba(255,255,255,0.07)", borderRadius: 8, padding: 2,
        }}>
          {PHASE_OPTIONS.map((o) => (
            <button key={o.value} onClick={() => setP(o.value)} style={{
              border: "none", background: p === o.value ? "rgba(255,255,255,0.16)" : "none",
              color: p === o.value ? "#fff" : "rgba(255,255,255,0.55)", borderRadius: 6,
              fontFamily: "var(--font)", fontSize: 11.5, fontWeight: 500, padding: "4px 11px", cursor: "pointer",
            }} lang="zh">{o.label}</button>
          ))}
        </div>
        <MainWindow player={player} variant="phases" />
      </div>
    );
  }

  function App() {
    const [screen, setScreen] = useState(() => ls.get("screen", "playing"));
    const [theme, setTheme] = useState(() => ls.get("theme", "dark"));
    const [time, setTime] = useState(() => ls.get("time", 30));
    const [playing, setPlaying] = useState(true);

    useEffect(() => ls.set("screen", screen), [screen]);
    useEffect(() => ls.set("theme", theme), [theme]);
    useEffect(() => ls.set("time", Math.round(time * 10) / 10), [time]);

    useEffect(() => {
      if (!playing) return;
      const iv = setInterval(() => setTime((t) => (t + 0.5 >= 88 ? 0 : t + 0.5)), 500);
      return () => clearInterval(iv);
    }, [playing]);

    const player = useMemo(() => ({
      time, playing,
      toggle: () => setPlaying((p) => !p),
      setTime: (t) => { setTime(t); setPlaying(true); },
    }), [time, playing]);

    const meta = FLAT.find((s) => s.id === screen) || FLAT[0];

    const renderScreen = () => {
      if (screen.startsWith("bgcard-")) return <MainWindow player={player} variant={screen} />;
      switch (screen) {
        case "empty":          return <MainEmpty />;
        case "playing":        return <MainWindow player={player} variant="playing" />;
        case "phases":         return <PhaseShowcase player={player} />;
        case "partial":        return <MainWindow player={player} variant="partial" />;
        case "more-menu":      return <MainWindow player={player} variant="more-menu" />;
        case "playlist-menu":  return <MainWindow player={player} variant="playlist-menu" />;
        case "hidden":         return <MainWindow player={player} variant="hidden" />;
        case "delete-sheet":   return <MainWindow player={player} variant="delete-sheet" />;
        case "blocked":        return <MainWindow player={player} variant="blocked" />;
        case "left-collapsed": return <MainWindow player={player} variant="left-collapsed" />;
        case "right-collapsed":return <MainWindow player={player} variant="right-collapsed" />;
        case "both-collapsed": return <MainWindow player={player} variant="both-collapsed" />;
        case "focus":          return <MainWindow player={player} variant="focus" />;
        case "lookup-toolbar": return <MainWindow player={player} variant="lookup-toolbar" />;
        case "gloss":          return <MainWindow player={player} variant="gloss" />;
        case "lookup-popover": return <MainWindow player={player} variant="lookup-popover" />;
        case "vocab":          return <MainWindow player={player} variant="vocab" />;
        case "edit-zh":        return <MainWindow player={player} variant="edit-zh" />;
        case "float-lookup":   return <FloatingWindow variant="lookup" player={player} />;
        case "float":             return <FloatingWindow variant="default" player={player} />;
        case "float-narrow":      return <FloatingWindow variant="narrow" player={player} />;
        case "float-transparent": return <FloatingWindow variant="transparent" player={player} />;
        case "lyrics-edit":       return <DesktopLyrics variant="edit" player={player} />;
        case "lyrics-locked":     return <DesktopLyrics variant="locked" player={player} />;
        case "lyrics-narrow":     return <DesktopLyrics variant="narrow" player={player} />;
        case "lyrics-transparent":return <DesktopLyrics variant="transparent" player={player} />;
        case "set-subs":    return <SettingsWindow initialTab="subs" />;
        case "set-sources": return <SettingsWindow initialTab="sources" />;
        case "set-trans":   return <SettingsWindow initialTab="translate" />;
        case "set-appear":  return <SettingsWindow initialTab="appearance" />;
        case "set-data":    return <SettingsWindow initialTab="data" />;
        case "app-menu":    return <AppMenus />;
        case "min-window":  return <MinWindow player={player} />;
        default:            return <MainWindow player={player} variant="playing" />;
      }
    };

    return (
      <div className="stage">
        <div className="stage-nav">
          <div className="stage-brand">
            <div className="stage-brand-name">EchoSub</div>
            <div className="stage-brand-sub" lang="zh">YouTube 双语字幕 · UI 设计稿 v0.1.2</div>
          </div>
          {SCREENS.map((g) => (
            <div key={g.group}>
              <div className="stage-group" lang="zh">{g.group}</div>
              {g.items.map((it) => {
                const idx = FLAT.findIndex((f) => f.id === it.id) + 1;
                return (
                  <button key={it.id} className={"stage-item" + (screen === it.id ? " active" : "")}
                          onClick={() => setScreen(it.id)}>
                    <span className="num">{String(idx).padStart(2, "0")}</span>
                    <span lang="zh">{it.label}</span>
                  </button>
                );
              })}
            </div>
          ))}
          <div className="stage-nav-foot">
            <div className="theme-toggle">
              <button className={theme === "dark" ? "on" : ""} onClick={() => setTheme("dark")} lang="zh">深色</button>
              <button className={theme === "light" ? "on" : ""} onClick={() => setTheme("light")} lang="zh">浅色</button>
            </div>
            <div style={{ fontSize: 10, color: "rgba(255,255,255,0.3)", padding: "0 4px" }} lang="zh">
              深浅色为设计展示；当前产品固定深色 · 播放模拟运行中
            </div>
          </div>
        </div>
        <div className="stage-canvas">
          <div className="stage-caption">
            <b>{String(FLAT.findIndex((s) => s.id === screen) + 1).padStart(2, "0")}</b>
            <span lang="zh">{meta.group} / {meta.label}</span>
          </div>
          <FitView resetKey={screen}>
            <div data-theme={theme} data-screen-label={meta.label}>
              {renderScreen()}
            </div>
          </FitView>
        </div>
      </div>
    );
  }

  ReactDOM.createRoot(document.getElementById("root")).render(<App />);
})();
