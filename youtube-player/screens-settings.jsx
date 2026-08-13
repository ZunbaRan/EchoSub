/* screens-settings.jsx — 设置窗口：字幕与语言 / 翻译服务 / 外观 / 缓存与隐私 */
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
          <Row title="目标翻译语言" desc="第一版支持简体中文">
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
        <div className="setnote" lang="zh">
          碎片化的机器字幕会按完整语义合并为 2～8 秒的短句；英文原文为第一阅读层级，中文译文为第二层级。
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
          <Row title="翻译服务" desc="使用你自己的 API Key，按用量由服务商计费">
            <SelectLike>OpenAI 兼容接口</SelectLike>
          </Row>
          <Row title="API Base URL" desc="高级选项，可指向自托管或代理服务">
            <div className="field" style={{ width: 230, height: 26 }}>
              <input defaultValue="https://api.openai.com/v1" style={{ fontSize: 11.5 }} />
            </div>
          </Row>
          <Row title="模型名称">
            <div className="field" style={{ width: 230, height: 26 }}>
              <input defaultValue="gpt-4o-mini" style={{ fontSize: 11.5 }} />
            </div>
          </Row>
          <Row title="API Key" desc="仅存储在 macOS Keychain，不写入任何配置文件">
            <div className="keyfield">
              <div className="field"><IconKey size={12} /><input type="password" defaultValue="your-api-key" /></div>
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
          翻译按小批量逐句生成并缓存，不阻塞视频播放；视频标题与字幕文本会发送给你配置的服务。未配置时英文字幕仍正常工作。
        </div>
      </React.Fragment>
    );
  }

  /* ---------- 悬浮字幕与桌面歌词 ---------- */
  function AppearanceSettings() {
    const [pin, setPin] = useState(true);
    const [spaces, setSpaces] = useState(true);
    const [plate, setPlate] = useState(true);
    const [sw, setSw] = useState(0);
    return (
      <React.Fragment>
        <h2 lang="zh">悬浮字幕与桌面歌词</h2>
        <div className="setgroup">
          <Row title="字号" desc="悬浮窗与桌面歌词共用">
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <div className="slider"><div className="fillp" style={{ width: "55%" }} /><div className="knobp" style={{ left: "55%" }} /></div>
              <span style={{ fontSize: 11, color: "var(--text-2)", width: 30 }}>中</span>
            </div>
          </Row>
          <Row title="文字颜色">
            <div className="swatches">
              {["#ffffff", "#ffd60a", "#30d158", "#64d2ff"].map((c, i) => (
                <button key={c} className={"swatch" + (sw === i ? " on" : "")} style={{ background: c }} onClick={() => setSw(i)} />
              ))}
            </div>
          </Row>
          <Row title="半透明底板" desc="桌面歌词在复杂背景上保持可读">
            <Switch on={plate} onChange={setPlate} />
          </Row>
          <Row title="默认 Pin 置顶" desc="悬浮字幕窗始终置于其他应用之上">
            <Switch on={pin} onChange={setPin} />
          </Row>
          <Row title="在所有桌面空间显示" desc="切换桌面时悬浮窗保持可见">
            <Switch on={spaces} onChange={setSpaces} />
          </Row>
          <Row title="锁定 / 解锁桌面歌词" desc="锁定后窗口穿透鼠标">
            <span style={{
              fontSize: 11, fontWeight: 600, background: "var(--fill)",
              border: "0.5px solid var(--panel-border)", borderRadius: 5, padding: "3px 8px",
            }}>⌘⇧L</span>
          </Row>
        </div>
        <div className="setnote" lang="zh">
          多显示器环境下记住桌面歌词所在屏幕；可分别调整英文与中文的上下顺序和对齐方式。
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
          <Row title="播放记录" desc="播放列表、观看进度与窗口位置">
            <Btn>清除全部播放记录</Btn>
          </Row>
          <Row title="恢复默认设置">
            <Btn>恢复默认…</Btn>
          </Row>
        </div>
        <div className="setgroup">
          <Row title="隐私说明" desc="EchoSub 不上传播放列表、观看历史或窗口设置">
            <Badge kind="ok" dot>仅保存在本机</Badge>
          </Row>
        </div>
        <div className="setnote" lang="zh">
          应用不要求登录 Google 或 YouTube。视频播放由 YouTube 嵌入播放器提供，YouTube 可能按其政策处理播放数据。
          使用 AI 翻译时，字幕文本仅发送给你配置的翻译服务。API Key 只存储在 macOS Keychain。
        </div>
      </React.Fragment>
    );
  }

  const TABS = [
    { id: "subs", label: "字幕与语言", icon: IconCaptions, el: SubtitleSettings },
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
