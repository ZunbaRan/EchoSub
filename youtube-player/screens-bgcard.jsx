/* screens-bgcard.jsx — 视频背景卡：覆盖右侧字幕面板的浮层
   状态：empty（未生成）/ generating（生成中）/ ready（完成-阅读）/ editing（编辑）/ error（失败） */
(function () {
  const { useState, useEffect, useRef } = React;

  function Section({ title, count, warn, children, defaultOpen }) {
    const [open, setOpen] = useState(!!defaultOpen);
    return (
      <div className="bg-sec">
        <button className="bg-sec-head" onClick={() => setOpen(!open)}>
          <IconChevronD size={11} style={{ opacity: 0.5, transform: open ? "none" : "rotate(-90deg)", transition: "transform 0.15s" }} />
          <span lang="zh">{title}</span>
          {count != null && <span className="cnt">{count}</span>}
          {warn && <IconAlert size={12} className="warnic" style={{ color: "var(--orange)" }} />}
          <span style={{ flex: 1 }} />
        </button>
        {open && <div className="bg-sec-body">{children}</div>}
      </div>
    );
  }

  function BgMenu({ onClose, onRegen, onCopy }) {
    return (
      <div className="ctxmenu" style={{ top: 36, right: 34 }} onMouseLeave={onClose}>
        <button className="ctx-item" onClick={onRegen}><span lang="zh">重新生成背景卡…</span></button>
        <button className="ctx-item" onClick={onCopy}><span lang="zh">复制背景卡</span></button>
      </div>
    );
  }

  function BackgroundCard({ phase, onClose, onSeek, onPhaseChange }) {
    const [menu, setMenu] = useState(false);
    const [confirm, setConfirm] = useState(false);
    const [edited, setEdited] = useState(false);
    const [summary, setSummary] = useState(BG_CARD.summary);
    const [domain, setDomain] = useState(BG_CARD.domain.body);

    /* ---- 未生成 ---- */
    if (phase === "empty") {
      return (
        <div className="bgcard">
          <Head onClose={onClose} />
          <div className="bgcard-center">
            <div className="ic-wrap" style={{ width: 44, height: 44, borderRadius: 12, background: "var(--fill)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--accent-strong)" }}>
              <IconSparkle size={22} />
            </div>
            <div className="bt" lang="zh">让翻译先读懂整个视频</div>
            <div className="bd" lang="zh">
              生成视频背景卡后，模型会带着全文概括、章节、术语和人物信息逐句翻译，长视频的人名、术语会更一致。
            </div>
            <Btn primary onClick={() => onPhaseChange && onPhaseChange("generating")}><IconSparkle size={13} />开始分析</Btn>
            <div style={{ fontSize: 10, color: "var(--text-3)" }} lang="zh">分析期间视频可正常播放</div>
          </div>
        </div>
      );
    }

    /* ---- 生成中 ---- */
    if (phase === "generating") {
      return (
        <div className="bgcard">
          <Head onClose={onClose} />
          <div className="bgcard-center">
            <div className="spinner" style={{ width: 20, height: 20, borderWidth: 2.5 }} />
            <div className="bt" lang="zh">正在理解完整视频内容…</div>
            <div className="bd" lang="zh">模型正在通读全部 1333 句字幕，提炼概括、章节与术语。视频播放不受影响。</div>
          </div>
        </div>
      );
    }

    /* ---- 失败 ---- */
    if (phase === "error") {
      return (
        <div className="bgcard">
          <Head onClose={onClose} />
          <div className="bgcard-center">
            <div style={{ width: 44, height: 44, borderRadius: 12, background: "rgba(255,159,10,0.14)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--orange)" }}>
              <IconAlert size={22} />
            </div>
            <div className="bt" lang="zh">背景卡生成失败</div>
            <div className="bd" lang="zh">翻译服务连接超时（第 2 次尝试后放弃）。字幕翻译仍可使用局部上下文，不受影响。</div>
            <Btn primary onClick={() => onPhaseChange && onPhaseChange("generating")}><IconRefresh size={13} />重新生成</Btn>
          </div>
        </div>
      );
    }

    /* ---- 完成 / 编辑 ---- */
    const editing = phase === "editing";
    return (
      <div className="bgcard">
        <div className="bgcard-head" style={{ position: "relative" }}>
          <span className="h" lang="zh">视频背景</span>
          {editing
            ? <Btn primary style={{ height: 24, fontSize: 11 }} onClick={() => { setEdited(true); onPhaseChange("ready"); }}>完成</Btn>
            : <Btn style={{ height: 24, fontSize: 11 }} onClick={() => onPhaseChange("editing")} lang="zh">编辑</Btn>}
          <IconBtn title="更多" onClick={() => setMenu(!menu)}><IconMore size={14} /></IconBtn>
          <IconBtn title="关闭" onClick={onClose}><IconX size={13} /></IconBtn>
          {menu && (
            <BgMenu
              onClose={() => setMenu(false)}
              onCopy={() => setMenu(false)}
              onRegen={() => { setMenu(false); setConfirm(true); }}
            />
          )}
        </div>
        <div className="bgcard-body">
          <div className="bgcard-meta">
            {BG_CARD.meta}{edited && <React.Fragment> · <span className="edited" lang="zh">已编辑</span></React.Fragment>}
          </div>

          <Section title="全文概括" defaultOpen>
            {editing
              ? <div className="bg-edit"><textarea rows={5} value={summary} onChange={(e) => setSummary(e.target.value)} /></div>
              : <p lang="zh">{summary}</p>}
          </Section>

          <Section title="章节概览" defaultOpen>
            {editing
              ? <div className="bg-edit" style={{ display: "flex", flexDirection: "column", gap: 5 }}>
                  {BG_CARD.chapters.map((c, i) => <input key={i} defaultValue={c.title} />)}
                </div>
              : BG_CARD.chapters.map((c, i) => (
                  <button key={i} className="bg-chapter" onClick={() => onSeek && onSeek(c.start)}>
                    <span className="ch-ts">{c.t}</span><span className="ch-t" lang="zh">{c.title}</span>
                  </button>
                ))}
          </Section>

          <Section title={BG_CARD.domain.title}>
            {editing
              ? <div className="bg-edit"><textarea rows={3} value={domain} onChange={(e) => setDomain(e.target.value)} /></div>
              : <p lang="zh">{domain}</p>}
          </Section>

          <Section title={BG_CARD.people.title} count={BG_CARD.people.count}>
            {BG_CARD.people.items.map((p, i) => <div key={i} className="bg-term" lang="zh">{p}</div>)}
          </Section>

          <Section title={BG_CARD.terms.title} count={BG_CARD.terms.count}>
            {BG_CARD.terms.items.map((t, i) => <div key={i} className="bg-term">{t}</div>)}
          </Section>

          <Section title={BG_CARD.issues.title} count={BG_CARD.issues.count} warn>
            {BG_CARD.issues.items.map((t, i) => <div key={i} className="bg-term" style={{ color: "var(--orange)" }} lang="zh">{t}</div>)}
          </Section>
        </div>
        <div className="bgcard-foot" lang="zh">{BG_CARD.footer}</div>

        {confirm && (
          <div className="sheet-overlay" onClick={() => setConfirm(false)}>
            <div className="sheet" onClick={(e) => e.stopPropagation()}>
              <div className="sh-t"><IconSparkle size={15} style={{ color: "var(--accent-strong)" }} /><span lang="zh">重新生成背景卡？</span></div>
              {edited ? (
                <React.Fragment>
                  <div className="sh-d" lang="zh">你编辑过这张背景卡。重新生成会覆盖概括、章节与表达风格；可以选择保留你修改过的术语表。</div>
                  <div className="sh-a">
                    <Btn onClick={() => setConfirm(false)} lang="zh">取消</Btn>
                    <Btn onClick={() => { setConfirm(false); onPhaseChange("generating"); }} lang="zh">全部覆盖</Btn>
                    <Btn primary onClick={() => { setConfirm(false); onPhaseChange("generating"); }} lang="zh">保留术语并重新生成</Btn>
                  </div>
                </React.Fragment>
              ) : (
                <React.Fragment>
                  <div className="sh-d" lang="zh">将使用当前翻译模型重新分析全部字幕，替换现有背景卡。</div>
                  <div className="sh-a">
                    <Btn onClick={() => setConfirm(false)} lang="zh">取消</Btn>
                    <Btn primary onClick={() => { setConfirm(false); onPhaseChange("generating"); }} lang="zh">重新生成</Btn>
                  </div>
                </React.Fragment>
              )}
            </div>
          </div>
        )}
      </div>
    );
  }

  function Head({ onClose }) {
    return (
      <div className="bgcard-head">
        <span className="h" lang="zh">视频背景</span>
        <IconBtn title="关闭" onClick={onClose}><IconX size={13} /></IconBtn>
      </div>
    );
  }

  Object.assign(window, { BackgroundCard });
})();
