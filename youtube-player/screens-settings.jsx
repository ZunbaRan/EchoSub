/* screens-settings.jsx — v0.1.2 设置窗口：
   字幕与语言 / 字幕来源（新增）/ 翻译服务 / 外观（配色预设+独立字号）/ 缓存与隐私（明文 credentials.json） */
(function () {
  const { useState } = React;

  function Row({ title, desc, children }) {
    return (
      <div className="setrow">
        <div className="lab">
          <div className="lt" lang="zh">{title}</div>
          {desc && <div className="ld" lang="zh">{desc}</div>}
        </div>
        {children}
      </div>
    );
  }

  function SelectLike({ children }) {
    return <span className="select-like">{children}<IconChevronD size={11} style={{ opacity: 0.5 }} /></span>;
  }

  function SliderCtl({ value, onChange, label }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div className="slider" style={{ cursor: "pointer" }}
             onClick={(e) => {
               const r = e.currentTarget.getBoundingClientRect();
               onChange(Math.round(Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * 100));
             }}>
          <div className="fillp" style={{ width: value + "%" }} />
          <div className="knobp" style={{ left: value + "%" }} />
        </div>
        <span style={{ fontSize: 11, color: "var(--text-2)", width: 38, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{label}</span>
      </div>
    );
  }

  /* ---------- 字幕与语言 ---------- */
  function SubtitleSettings() {
    const [follow, setFollow] = useState(true);
    const [mode, setMode] = useState("both");
    return (
      <React.Fragment>
        <h2 lang="zh">字幕与语言</h2>
        <div className="setgroup">
          <Row title="首选原字幕语言" desc="优先获取该语言的人工字幕，其次自动生成字幕">
            <SelectLike>英语</SelectLike>
          </Row>
          <Row title="目标翻译语言">
            <SelectLike>简体中文</SelectLike>
          </Row>
          <Row title="默认字幕模式">
            <Seg
              options={[{ value: "en", label: "原文" }, { value: "zh", label: "中文" }, { value: "both", label: "双语" }]}
              value={mode} onChange={setMode}
            />
          </Row>
          <Row title="自动跟随播放" desc="关闭后，字幕面板默认不随播放滚动">
            <Switch on={follow} onChange={setFollow} />
          </Row>
        </div>
      </React.Fragment>
    );
  }

  /* ---------- 字幕来源（新增） ---------- */
  function SourcesSettings() {
    const [installed, setInstalled] = useState(true);
    return (
      <React.Fragment>
        <h2 lang="zh">字幕来源</h2>
        <div className="setnote" lang="zh" style={{ marginTop: -4, marginBottom: 10 }}>
          按以下顺序回退；公开视频不要求 YouTube 登录。
        </div>
        <div className="src-flow">
          <span className="src-node">内置 YouTube</span>
          <span className="arrow">→</span>
          <span className="src-node">本机 yt-dlp</span>
          <span className="arrow">→</span>
          <span className="src-node last">Supadata</span>
        </div>
        <div className="setgroup">
          <Row title="内置 YouTube" desc="首选来源，直接读取视频的人工或自动字幕">
            <Badge kind="ok" dot>可用</Badge>
          </Row>
          <Row title="本机 yt-dlp" desc={installed ? "已检测到，内置方式失败时自动使用" : "未安装时跳过该来源"}>
            {installed
              ? <Badge kind="ok" dot>已检测</Badge>
              : <Badge kind="warn" dot>未安装</Badge>}
          </Row>
          {!installed && (
            <Row title="安装 yt-dlp">
              <span className="code-inline">brew install yt-dlp</span>
            </Row>
          )}
          <Row title="Supadata API Key" desc="仅在前两种方式失败后使用；以 mode=native 只读取已有字幕，不会触发 AI 转写费用">
            <div className="keyfield">
              <div className="field" style={{ width: 200 }}><IconKey size={12} /><input type="password" placeholder="粘贴 API Key" /></div>
            </div>
          </Row>
        </div>
        <div className="setnote" lang="zh">
          演示开关：
          <button className="ctx-item" style={{ display: "inline-flex", padding: "2px 8px", fontSize: 10.5 }}
                  onClick={() => setInstalled(!installed)} lang="zh">
            切换 yt-dlp {installed ? "未安装" : "已检测"}状态
          </button>
        </div>
      </React.Fragment>
    );
  }

  /* ---------- 翻译服务 ---------- */
  function TranslateSettings() {
    const [tested, setTested] = useState(false);
    return (
      <React.Fragment>
        <h2 lang="zh">翻译服务</h2>
        <div className="setgroup">
          <Row title="翻译服务">
            <SelectLike>OpenAI 兼容接口</SelectLike>
          </Row>
          <Row title="API Base URL" desc="支持粘贴">
            <div className="field" style={{ width: 230, height: 26 }}>
              <input defaultValue="https://api.deepseek.com/v1" style={{ fontSize: 11.5 }} />
            </div>
          </Row>
          <Row title="模型名称" desc="常用：DeepSeek V4 Flash、Qwen3 系列">
            <div className="field" style={{ width: 230, height: 26 }}>
              <input defaultValue="deepseek-v4-flash" style={{ fontSize: 11.5 }} />
            </div>
          </Row>
          <Row title="API Key" desc="支持粘贴；保存在本机数据文件夹（见「缓存与隐私」）">
            <div className="keyfield">
              <div className="field"><IconKey size={12} /><input type="password" placeholder="粘贴 API Key" /></div>
              <Btn onClick={() => setTested(true)}>测试连接</Btn>
            </div>
          </Row>
          {tested && (
            <Row title="连接状态">
              <span style={{ display: "inline-flex", alignItems: "center", gap: 7, fontSize: 11.5, color: "var(--green)" }}>
                <span className="dotok" />连接成功 · 延迟 320ms
              </span>
            </Row>
          )}
        </div>
        <div className="setnote" lang="zh">
          普通字幕翻译会关闭模型的显式思考；生成视频背景卡时开启思考模式。翻译按每批 12 句进行，失败的批次可跳过并在之后补全。
        </div>
      </React.Fragment>
    );
  }

  /* ---------- 外观 ---------- */
  function AppearanceSettings() {
    const [floatSize, setFloatSize] = useState(40);
    const [lyEn, setLyEn] = useState(56);
    const [lyZh, setLyZh] = useState(30);
    const [floatOp, setFloatOp] = useState(96);
    const [lyOp, setLyOp] = useState(72);
    const [pin, setPin] = useState(true);
    const [spaces, setSpaces] = useState(true);
    const [preset, setPreset] = useState(0);
    const custom = preset === "custom";
    return (
      <React.Fragment>
        <h2 lang="zh">外观</h2>
        <div className="setgroup">
          <Row title="悬浮字幕字号" desc="12–36，中文自动小 3">
            <SliderCtl value={(floatSize / 96) * 100} onChange={setFloatSize} label="15" />
          </Row>
          <Row title="桌面歌词英文字号" desc="12–48，默认 27">
            <SliderCtl value={lyEn} onChange={setLyEn} label="27" />
          </Row>
          <Row title="桌面歌词中文字号" desc="12–48，默认 18">
            <SliderCtl value={lyZh} onChange={setLyZh} label="18" />
          </Row>
          <Row title="悬浮字幕背景透明度" desc="拖到 0% 为完全透明">
            <SliderCtl value={floatOp} onChange={setFloatOp} label={floatOp + "%"} />
          </Row>
          <Row title="桌面歌词背景透明度">
            <SliderCtl value={lyOp} onChange={setLyOp} label={lyOp + "%"} />
          </Row>
        </div>

        <div className="setgroup">
          <Row title="配色预设" desc="英文、中文两个字体颜色，同时应用于字幕面板、悬浮字幕与桌面歌词" />
          <div style={{ padding: "2px 13px 12px" }}>
            <div className="preset-grid">
              {COLOR_PRESETS.map((p, i) => (
                <button key={p.name} className={"preset" + (preset === i ? " on" : "")} onClick={() => setPreset(i)}>
                  <span className="pdots">
                    <span className="pdot" style={{ background: p.en }} />
                    <span className="pdot" style={{ background: p.zh }} />
                  </span>
                  <span className="pbars">
                    <span className="pbar" style={{ background: p.en }} />
                    <span className="pbar short" style={{ background: p.zh }} />
                  </span>
                  <span className="pname" lang="zh">{p.name}</span>
                </button>
              ))}
              <button className={"preset" + (custom ? " on" : "")} onClick={() => setPreset("custom")}>
                <span className="pdots">
                  <span className="pdot" style={{ background: "conic-gradient(#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00)" }} />
                  <span className="pdot" style={{ background: "conic-gradient(#0ff,#00f,#f0f,#f00,#ff0,#0f0,#0ff)" }} />
                </span>
                <span className="pbars">
                  <span className="pbar" style={{ background: "linear-gradient(90deg,#fff,#888)" }} />
                  <span className="pbar short" style={{ background: "linear-gradient(90deg,#ccc,#666)" }} />
                </span>
                <span className="pname" lang="zh">自定义</span>
              </button>
            </div>
          </div>
          {custom && (
            <React.Fragment>
              <Row title="英文字体颜色">
                <button className="colorwell" style={{ background: "#FFF8E7" }} />
              </Row>
              <Row title="中文字体颜色">
                <button className="colorwell" style={{ background: "#FFB74D" }} />
              </Row>
            </React.Fragment>
          )}
        </div>

        <div className="setgroup">
          <Row title="悬浮窗默认 Pin" desc="置顶后切换其他应用仍可见">
            <Switch on={pin} onChange={setPin} />
          </Row>
          <Row title="在所有桌面空间显示">
            <Switch on={spaces} onChange={setSpaces} />
          </Row>
        </div>
      </React.Fragment>
    );
  }

  /* ---------- 缓存与隐私 ---------- */
  function DataSettings() {
    return (
      <React.Fragment>
        <h2 lang="zh">缓存与隐私</h2>
        <div className="setgroup">
          <Row title="字幕与翻译缓存" desc="12 个视频 · 共 38 MB，离线可继续阅读">
            <Btn>清除字幕缓存</Btn>
          </Row>
          <Row title="播放记录" desc="播放列表、隐藏列表、观看进度与窗口位置">
            <Btn>清除全部播放记录</Btn>
          </Row>
          <Row title="恢复默认设置">
            <Btn>恢复默认…</Btn>
          </Row>
        </div>

        <div className="setgroup">
          <Row title="本机数据位置" desc="可通过菜单「显示本地数据文件夹」打开">
            <Btn><IconFolder size={13} />显示本地数据文件夹</Btn>
          </Row>
          <div style={{ padding: "2px 13px 12px" }}>
            <div className="code-inline" style={{ display: "block", padding: "9px 11px", lineHeight: 1.8 }}>
              ~/Library/Application Support/EchoSub/<br />
              ├─ library.json<br />
              ├─ credentials.json<br />
              ├─ diagnostics.jsonl<br />
              └─ diagnostics.previous.jsonl
            </div>
          </div>
          <Row title="密钥存储" desc="credentials.json 为明文文件，权限已设为 0600（仅当前用户可读）">
            <Badge kind="ok" dot>仅保存在本机</Badge>
          </Row>
          <Row title="诊断日志" desc="排查长视频翻译进度的主要途径">
            <Btn><IconDocText size={13} />打开诊断日志</Btn>
          </Row>
        </div>
        <div className="setnote" lang="zh">
          应用不要求登录 Google 或 YouTube。视频播放由 YouTube 嵌入播放器提供，YouTube 可能按其政策处理播放数据。
          翻译时字幕文本仅发送给你配置的翻译服务。播放列表、观看历史与窗口设置不会上传到开发者服务器。
        </div>
      </React.Fragment>
    );
  }

  const TABS = [
    { id: "subs", label: "字幕与语言", icon: IconCaptions, el: SubtitleSettings },
    { id: "sources", label: "字幕来源", icon: IconRestore, el: SourcesSettings },
    { id: "translate", label: "翻译服务", icon: IconTranslate, el: TranslateSettings },
    { id: "appearance", label: "外观", icon: IconDisplay, el: AppearanceSettings },
    { id: "data", label: "缓存与隐私", icon: IconKey, el: DataSettings },
  ];

  function SettingsWindow({ initialTab }) {
    const [tab, setTab] = useState(initialTab || "subs");
    const Active = TABS.find((t) => t.id === tab).el;
    return (
      <Window width={640} height={600} title="EchoSub 设置">
        <div className="setwin-body">
          <div className="setnav">
            {TABS.map((t) => {
              const Ico = t.icon;
              return (
                <button key={t.id} className={"setnav-item" + (tab === t.id ? " on" : "")} onClick={() => setTab(t.id)}>
                  <span className="ic"><Ico size={14} /></span><span lang="zh">{t.label}</span>
                </button>
              );
            })}
          </div>
          <div className="setpanel"><Active /></div>
        </div>
      </Window>
    );
  }

  Object.assign(window, { SettingsWindow });
})();
