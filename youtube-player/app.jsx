/* app.jsx — 设计稿舞台：画面索引、深浅色切换、播放模拟（状态持久化到 localStorage） */
(function () {
  const { useState, useEffect, useMemo } = React;

  const SCREENS = [
    { group: "主窗口", items: [
      { id: "empty",      label: "空状态 / 首次打开" },
      { id: "playing",    label: "播放 + 双语字幕（跟随中）" },
      { id: "paused",     label: "手动滚动 · 暂停跟随" },
      { id: "translating",label: "原文已显示 · 逐句翻译中" },
      { id: "collapsed",  label: "播放列表折叠" },
      { id: "nosub",      label: "视频无字幕" },
      { id: "blocked",    label: "禁止嵌入 · 在 YouTube 打开" },
    ]},
    { group: "字幕窗口", items: [
      { id: "float",        label: "悬浮字幕窗 · 默认" },
      { id: "float-pin",    label: "悬浮字幕窗 · Pin 置顶" },
      { id: "float-scroll", label: "悬浮字幕窗 · 手动滚动" },
      { id: "lyrics-edit",  label: "桌面歌词 · 编辑状态" },
      { id: "lyrics-lock",  label: "桌面歌词 · 锁定状态" },
    ]},
    { group: "设置", items: [
      { id: "set-subs",   label: "字幕与语言" },
      { id: "set-trans",  label: "翻译服务" },
      { id: "set-appear", label: "悬浮窗与桌面歌词外观" },
      { id: "set-data",   label: "缓存与隐私" },
    ]},
  ];
  const FLAT = SCREENS.flatMap((g) => g.items.map((it) => ({ ...it, group: g.group })));

  const ls = {
    get(k, d) { try { const v = localStorage.getItem("echosub-" + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("echosub-" + k, JSON.stringify(v)); } catch (e) {} },
  };

  // 画面超出舞台时等比缩小适配（设计稿展示用，不影响产品尺寸标注）
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
      const t = setTimeout(measure, 50);
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

  function App() {
    const [screen, setScreen] = useState(() => ls.get("screen", "playing"));
    const [theme, setTheme] = useState(() => ls.get("theme", "dark"));
    const [time, setTime] = useState(() => ls.get("time", 22.4));
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
      switch (screen) {
        case "empty":       return <MainEmpty />;
        case "playing":     return <MainWindow variant="playing" player={player} />;
        case "paused":      return <MainWindow variant="paused-follow" player={player} />;
        case "translating": return <MainWindow variant="translating" player={player} />;
        case "collapsed":   return <MainWindow variant="collapsed" player={player} />;
        case "nosub":       return <MainWindow variant="nosub" player={player} />;
        case "blocked":     return <MainWindow variant="blocked" player={player} />;
        case "float":        return <FloatingWindow variant="default" player={player} />;
        case "float-pin":    return <FloatingWindow variant="pinned" player={player} />;
        case "float-scroll": return <FloatingWindow variant="scrolled" player={player} />;
        case "lyrics-edit":  return <DesktopLyrics variant="edit" player={player} />;
        case "lyrics-lock":  return <DesktopLyrics variant="locked" player={player} />;
        case "set-subs":   return <SettingsWindow initialTab="subs" />;
        case "set-trans":  return <SettingsWindow initialTab="translate" />;
        case "set-appear": return <SettingsWindow initialTab="appearance" />;
        case "set-data":   return <SettingsWindow initialTab="data" />;
        default:           return <MainWindow variant="playing" player={player} />;
      }
    };

    return (
      <div className="stage">
        <div className="stage-nav">
          <div className="stage-brand">
            <div className="stage-brand-name">EchoSub</div>
            <div className="stage-brand-sub" lang="zh">YouTube 双语字幕 · UI 设计稿 v1</div>
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
              播放模拟运行中 · 点击字幕行可跳转
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
