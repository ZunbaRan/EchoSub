/* chrome.jsx — 窗口骨架与通用控件（主窗口/设置窗口共用） */
(function () {
  const { useState } = React;

  function TrafficLights() {
    return (
      <div className="tlights">
        <div className="tlight r" /><div className="tlight y" /><div className="tlight g" />
      </div>
    );
  }

  // 通用窗口骨架
  function Window({ width, height, title, titleRight, children, style }) {
    return (
      <div className="win es-root" style={{ width, height, ...style }}>
        <div className="win-titlebar">
          <TrafficLights />
          {title != null && <div className="win-title">{title}</div>}
          <div style={{ flex: 1 }} />
          {titleRight}
        </div>
        {children}
      </div>
    );
  }

  function Btn({ children, primary, icon, toggled, onClick, style, title }) {
    const cls = "btn" + (primary ? " primary" : "") + (icon ? " icon" : "") + (toggled ? " toggled" : "");
    return <button className={cls} onClick={onClick} style={style} title={title}>{children}</button>;
  }

  function IconBtn({ children, on, onClick, title }) {
    return <button className={"iconbtn" + (on ? " on" : "")} onClick={onClick} title={title}>{children}</button>;
  }

  function Seg({ options, value, onChange }) {
    return (
      <div className="seg">
        {options.map((o) => (
          <button key={o.value} className={value === o.value ? "on" : ""} onClick={() => onChange(o.value)}>
            {o.label}
          </button>
        ))}
      </div>
    );
  }

  function Switch({ on, onChange }) {
    return <button className={"switch" + (on ? " on" : "")} onClick={() => onChange(!on)} aria-pressed={on} />;
  }

  // 链接输入框（标题栏 / 空状态共用）
  function LinkField({ focused, compact, value, onChange, error }) {
    const [innerFocus, setInnerFocus] = useState(false);
    const isFocus = focused || innerFocus;
    return (
      <div className={"field" + (isFocus ? " focused" : "")} style={compact ? { width: 300 } : { flex: 1 }}>
        <IconLink size={13} />
        <input
          placeholder="粘贴 YouTube 链接开始…"
          value={value}
          onChange={(e) => onChange && onChange(e.target.value)}
          onFocus={() => setInnerFocus(true)}
          onBlur={() => setInnerFocus(false)}
        />
        <IconPaste size={13} style={{ opacity: 0.5 }} />
      </div>
    );
  }

  function Badge({ kind, children, dot }) {
    return <span className={"badge " + kind + (dot ? " dot" : "")}>{children}</span>;
  }

  Object.assign(window, { TrafficLights, Window, Btn, IconBtn, Seg, Switch, LinkField, Badge });
})();
