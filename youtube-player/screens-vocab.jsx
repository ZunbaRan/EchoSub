/* screens-vocab.jsx — 选词讲解：选区工具条 / 内联直译 / 详解 Popover / 本片词汇面板 / 编辑译文 */
(function () {
  const { useState, useEffect, useRef } = React;

  /* 选区快捷工具条（PopClip 式，出现在英文选区上方；directOnly 用于悬浮窗） */
  function SelectionToolbar({ style, onDirect, onDetail, directOnly }) {
    return (
      <div className="sel-toolbar" style={style}>
        <button className="sel-btn" onClick={onDirect}>
          <IconSparkle size={12} /><span lang="zh">直译</span>
        </button>
        {!directOnly && (
          <React.Fragment>
            <span className="sel-sep" />
            <button className="sel-btn" onClick={onDetail}>
              <span lang="zh">详解</span><IconChevronD size={10} style={{ transform: "rotate(-90deg)", opacity: 0.6 }} />
            </button>
          </React.Fragment>
        )}
      </div>
    );
  }

  /* 内联直译：追加在中文翻译之后（第三阅读层级） */
  function GlossEntries({ entries, onOpen, onRemove }) {
    if (!entries || !entries.length) return null;
    return (
      <span className="gloss-line">
        <IconSparkle size={10} className="gloss-ic" />
        {entries.map((g, i) => (
          <span key={g.id} className="gloss-entry">
            {i > 0 && <span className="gloss-sep">┆</span>}
            <button className="gloss-chip" title="查看详解" onClick={(e) => { e.stopPropagation(); onOpen && onOpen(g); }}>
              <span className="gw" lang="en">{g.w}</span>
              <span className="gg" lang="zh">{g.g}</span>
            </button>
            <button className="gloss-x" title="移除" onClick={(e) => { e.stopPropagation(); onRemove && onRemove(g); }}>
              <IconX size={9} />
            </button>
          </span>
        ))}
      </span>
    );
  }

  /* 详解 Popover（锚定卡片，保持字幕上下文可见） */
  function VocabPopover({ style, onClose, onSeekSentence }) {
    const d = VOCAB_DETAIL;
    const [tab, setTab] = useState(null); // 链式查词演示：点击同根词/近义词
    return (
      <div className="vocab-popover" style={style}>
        <div className="vp-head">
          <div className="vp-word-row">
            <span className="vp-word" lang="en">{tab || d.word}</span>
            <span className="vp-pos">{d.pos}</span>
            <span style={{ flex: 1 }} />
            <IconBtn title="关闭（Esc）" onClick={onClose}><IconX size={12} /></IconBtn>
          </div>
          <div className="vp-phonetic">发音: <span lang="en">{d.phonetic}</span></div>
          <div className="vp-gloss" lang="zh">{d.pos} {d.gloss}</div>
        </div>

        <div className="vp-body">
          <div className="vp-sec vp-context">
            <div className="vp-sec-t" lang="zh">在这里的意思</div>
            <div className="vp-sec-b" lang="zh">{d.contextual}</div>
            <button className="vp-sent" onClick={onSeekSentence}>
              <IconPlay size={10} />
              <span lang="en">From that day onwards, I decided to speak differently.</span>
              <span className="vp-sent-ts">01:24</span>
            </button>
          </div>

          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">时态</div>
            <div className="vp-sec-b">{d.forms}</div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">解释</div>
            <div className="vp-sec-b" lang="zh">{d.explanation}</div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">词源学</div>
            <div className="vp-sec-b" lang="zh">{d.etymology}</div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">记忆方法</div>
            <div className="vp-sec-b" lang="zh">{d.memory}</div>
          </div>

          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">同根词</div>
            <div className="vp-sec-b vp-chips">
              {d.cognates.map((c, i) => (
                <button key={i} className="vp-chip" title="继续查这个词" onClick={() => setTab(c.w)}>
                  <span className="pc-pos">{c.pos}</span><span lang="en">{c.w}</span><span className="pc-g" lang="zh">{c.g}</span>
                </button>
              ))}
            </div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">近义词</div>
            <div className="vp-sec-b vp-chips">
              {d.synonyms.map((s) => <button key={s} className="vp-chip" onClick={() => setTab(s)} lang="en">{s}</button>)}
            </div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">反义词</div>
            <div className="vp-sec-b vp-chips">
              {d.antonyms.map((s) => <button key={s} className="vp-chip dim" onClick={() => setTab(s)} lang="en">{s}</button>)}
            </div>
          </div>

          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">常用短语</div>
            <div className="vp-sec-b">
              {d.phrases.map((p, i) => (
                <div key={i} className="vp-phrase">
                  <span lang="en">{i + 1}. {p.p}</span> <span className="pc-g" lang="zh">{p.g}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="vp-sec">
            <div className="vp-sec-t" lang="zh">例句</div>
            <div className="vp-sec-b">
              {d.examples.map((ex, i) => (
                <div key={i} className="vp-ex">
                  <div lang="en">{i + 1}. {ex.en}</div>
                  <div className="vp-ex-zh" lang="zh">{ex.zh}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    );
  }

  /* 本片词汇：覆盖右侧字幕面板的汇总浮层（与背景卡同范式） */
  function VocabPanel({ onClose, onSeek, onOpen }) {
    return (
      <div className="bgcard">
        <div className="bgcard-head">
          <span className="h" lang="zh">本片词汇</span>
          <span style={{ fontSize: 10.5, color: "var(--text-3)" }}>{VOCAB_LIST.length}</span>
          <IconBtn title="关闭" onClick={onClose}><IconX size={13} /></IconBtn>
        </div>
        <div className="bgcard-body">
          <div className="bgcard-meta" lang="zh">你在本视频查过的词 · 直译已随字幕内联显示</div>
          {VOCAB_LIST.map((v) => {
            const sent = SUBTITLES.find((s) => s.id === v.sid);
            return (
              <div key={v.w} className="vocab-row">
                <button className="vocab-main" onClick={() => onOpen && onOpen(v)}>
                  <span className="vw" lang="en">{v.w}</span>
                  <span className="vp-pos">{v.pos}</span>
                  <span className="vg" lang="zh">{v.g}</span>
                </button>
                <button className="vocab-sent" title="跳转到这句" onClick={() => onSeek(v.start)}>
                  <span className="vs-ts">{v.ts}</span>
                  <span className="vs-t" lang="en">{sent && sent.en}</span>
                </button>
              </div>
            );
          })}
        </div>
        <div className="bgcard-foot" lang="zh">点击单词查看详解；点击句子跳转到对应时间。</div>
      </div>
    );
  }

  /* 编辑译文（仅中文可编辑，英文原文只读） */
  function EditZhBlock({ row, onSave, onCancel }) {
    const [text, setText] = useState(row.zh);
    const ref = useRef(null);
    useEffect(() => { if (ref.current) { ref.current.focus(); ref.current.select(); } }, []);
    return (
      <span className="zh-edit" onClick={(e) => e.stopPropagation()}>
        <textarea
          ref={ref}
          rows={3}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) onSave(text);
            if (e.key === "Escape") onCancel();
          }}
        />
        <span className="zh-edit-bar">
          <span className="zh-edit-hint" lang="zh">⌘Enter 保存 · Esc 取消</span>
          <span style={{ flex: 1 }} />
          <Btn style={{ height: 22, fontSize: 10.5 }} onClick={onCancel} lang="zh">取消</Btn>
          <Btn primary style={{ height: 22, fontSize: 10.5 }} onClick={() => onSave(text)} lang="zh">保存</Btn>
        </span>
      </span>
    );
  }

  Object.assign(window, { SelectionToolbar, GlossEntries, VocabPopover, VocabPanel, EditZhBlock });
})();
