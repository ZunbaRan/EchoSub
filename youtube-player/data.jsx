/* data.jsx — 演示数据 v0.1.2：播放列表（含隐藏）、长句双语字幕、背景卡、任务状态文案 */
(function () {
  // 状态 → 颜色语义（与产品一致）：idle 灰 / loading·translating 蓝 / ready 绿 / noSubtitles 橙 / failed 红
  const STATUS = {
    idle:        { kind: "mute", label: "待获取" },
    loading:     { kind: "busy", label: "获取中" },
    translating: { kind: "busy", label: "翻译中" },
    ready:       { kind: "ok",   label: "双语" },
    noSubtitles: { kind: "warn", label: "无字幕" },
    failed:      { kind: "err",  label: "失败" },
  };

  // 播放列表：可同时存在多个翻译任务（翻译任务按 videoID 独立登记）
  const VIDEOS = [
    { id: "v1", current: true,
      title: "How to Speak So That People Want to Listen",
      channel: "TED", duration: "9:58", progress: 0.34,
      status: "translating", hue: [216, 78, 52] },
    { id: "v2",
      title: "The Art of Slow Reading in a Fast World",
      channel: "The School of Life", duration: "12:41", progress: 0.82,
      status: "ready", hue: [262, 46, 48] },
    { id: "v3",
      title: "Inside the Mind of a Master Procrastinator",
      channel: "TED", duration: "14:03", progress: 0,
      status: "translating", hue: [174, 52, 40] },
    { id: "v4",
      title: "Why We Get Bored and What To Do About It",
      channel: "Veritasium", duration: "18:26", progress: 0,
      status: "noSubtitles", hue: [28, 72, 48] },
    { id: "v5",
      title: "Designing for Calm Technology",
      channel: "NN/g", duration: "7:52", progress: 0.12,
      status: "failed", hue: [340, 58, 50] },
    { id: "v6",
      title: "A Philosophy of Walking",
      channel: "Commencement", duration: "21:07", progress: 0,
      status: "idle", hue: [200, 30, 42] },
  ];

  // 已隐藏列表（隐藏 ≠ 删除：数据全部保留）
  const HIDDEN_VIDEOS = [
    { id: "h1", title: "How Languages Evolve Over Time", channel: "TED-Ed", duration: "5:12", status: "ready", hue: [150, 40, 40] },
    { id: "h2", title: "The Psychology of Procrastination", channel: "Sprouts", duration: "8:33", status: "ready", hue: [320, 36, 46] },
  ];

  // 字幕单元：含真实长句，覆盖 英文1行/中文1行、英文3行/中文2行、英文5行/中文3行 三种排版
  const SUBTITLES = [
    { id: "s01", start: 0,   end: 4.2,  en: "The human voice is the instrument we all play.", zh: "人声是我们每个人都会演奏的乐器。" },
    { id: "s02", start: 4.2, end: 9.6,  en: "It's the most powerful sound in the world, probably.", zh: "它大概是世界上最有力量的声音。" },
    { id: "s03", start: 9.6, end: 15.8, en: "It's the only one that can start a war, or say \"I love you.\"", zh: "它是唯一能发动战争，也能说出“我爱你”的声音。" },
    { id: "s04", start: 15.8, end: 22.4, en: "And yet, many people have the experience that when they speak, people don't listen to them.", zh: "然而很多人都有这样的体会：自己说话时，别人并不在听。" },
    { id: "s05", start: 22.4, end: 28.9, en: "Why is that? How can we speak powerfully to make change in the world?", zh: "为什么会这样？我们怎样说话才有力量，才能推动改变？" },
    { id: "s06", start: 28.9, end: 38.6, en: "What I'd like to suggest is that there are a number of habits that we need to move away from, and I've assembled for your pleasure here seven deadly sins of speaking — I'm not pretending this is an exhaustive list, but these seven, I think, are pretty large habits that we can all fall into.", zh: "我想说的是，有几个说话的习惯我们需要戒掉。我为大家总结了说话的七宗罪——这并不是一份完整清单，但这七条，我认为是我们都容易犯的大毛病。" },
    { id: "s07", start: 38.6, end: 43.2, en: "First, gossip. Speaking ill of somebody who's not present.", zh: "第一，八卦。在背后说别人的闲话。" },
    { id: "s08", start: 43.2, end: 52.7, en: "Not a nice habit, and we know perfectly well the person gossiping will be gossiping about us five minutes later.", zh: "这不是好习惯，而且我们心里很清楚，说别人闲话的人，五分钟后就会说我们。" },
    { id: "s09", start: 52.7, end: 64.9, en: "Second, judging. It's very hard to listen to somebody if you know that you're being judged and found wanting at the same time, and most of us have felt this in conversations that matter to us — at work, with friends, or with family — where the exchange quietly turns into a kind of trial, and we start editing ourselves instead of actually speaking.", zh: "第二，评判。如果你知道自己正被评判、被认定不够好，就很难再听对方说下去。在重要的谈话里——工作中、朋友间、家人间——我们大多经历过对话悄悄变成一场审判的时刻，于是我们开始修饰自己，而不是真正在说话。" },
    { id: "s10", start: 64.9, end: 71.4, en: "Negativity is another one. It's very hard to listen when everybody's that negative.", zh: "消极也是其中之一。当所有人都那么消极时，倾听会变得很难。" },
    { id: "s11", start: 71.4, end: 78.2, en: "And another form of negativity, complaining. Well, this is the national art of the U.K.", zh: "还有一种消极形式是抱怨。嗯，这可以说是英国的“国粹”。" },
    { id: "s12", start: 78.2, end: 84.0, en: "It's what we do to pass the time, but actually, complaining is viral misery.", zh: "我们靠抱怨打发时间，可实际上，抱怨是会传染的痛苦。" },
    { id: "s13", start: 84.0, end: 88.0, en: "From that day onwards, I decided to speak differently.", zh: "从那天起，我决定换一种方式说话。" },
  ];

  // 词汇直译（内联注释）：按字幕单元 ID 挂载，随字幕持久化显示
  const GLOSS_MAP = {
    s07: [{ id: "g1", w: "gossip", g: "八卦；闲话" }],
    s09: [{ id: "g2", w: "judging", g: "评判；品头论足" }],
    s13: [{ id: "g3", w: "onwards", g: "向前；前进；从那时起" }],
  };

  // 词汇详解（AI 生成，含语境义）
  const VOCAB_DETAIL = {
    word: "onwards", pos: "adv.", phonetic: "/ˈɒnwədz/",
    gloss: "向前；前进；从那时起",
    contextual: "在句中表示“从那天起”：from that day onwards = 从那天开始，之后一直持续。",
    forms: "（副词无时态变化）",
    explanation: "表示方向或时间上的“向前”，既可指空间上的移动，也可指时间上的延续或进展。",
    etymology: "源自中古英语“onwardes”，由“on”（在……上，向前）加表方向的副词后缀“-wards”（朝……方向）构成，与古英语“onweard”同源。最初仅指空间上的“向前移动”，后逐渐扩展至时间与抽象进展。现代英语中“onwards”与“onward”通用，但“onwards”在英式英语中更常见，多用于非正式或口语语境。",
    memory: "拆解为“on”（在……上）+“wards”（朝……方向），联想“踩在时间或道路的‘上面’继续朝前走”，即可记住“向前”的含义。",
    cognates: [{ w: "onward", pos: "adv.", g: "向前" }, { w: "onward", pos: "adj.", g: "向前的" }],
    synonyms: ["forward", "ahead", "forth"],
    antonyms: ["backwards", "backward"],
    phrases: [{ p: "from now onwards", g: "从现在起" }, { p: "onwards and upwards", g: "不断进步；蒸蒸日上" }],
    examples: [
      { en: "The crowd moved onwards towards the square.", zh: "人群向前涌向广场。" },
      { en: "From the 1990s onwards, the industry changed completely.", zh: "从九十年代起，这个行业彻底改变了。" },
    ],
  };

  // 本片词汇汇总（直译痕迹自然形成）
  const VOCAB_LIST = [
    { w: "instrument", pos: "n.", g: "乐器；工具", sid: "s01", ts: "00:00", start: 0 },
    { w: "gossip", pos: "n.", g: "八卦；闲话", sid: "s07", ts: "00:38", start: 38.6 },
    { w: "judging", pos: "v.", g: "评判；品头论足", sid: "s09", ts: "00:52", start: 52.7 },
    { w: "negativity", pos: "n.", g: "消极；否定性", sid: "s10", ts: "01:04", start: 64.9 },
    { w: "viral", pos: "adj.", g: "病毒式传播的", sid: "s12", ts: "01:18", start: 78.2 },
    { w: "onwards", pos: "adv.", g: "向前；前进；从那时起", sid: "s13", ts: "01:24", start: 84 },
  ];

  // 待补全：部分句子缺中文（翻译完成但有漏翻）
  function subtitlesPartial() {
    return SUBTITLES.map((s, i) => ([2, 5, 8].includes(i) ? { ...s, zh: null } : s));
  }

  // 右侧面板底部任务反馈文案
  const PHASE_FOOTER = {
    fetching:    { text: "正在获取字幕…", spinner: true },
    analyzing:   { text: "正在理解完整视频内容…", spinner: true },
    translating: { text: "正在翻译 168 / 1333 句", progress: 168 / 1333 },
    ready:       { text: "YouTube · YouTube 人工字幕" },
    partial:     { text: "YouTube · YouTube 自动字幕 · 待补全 12 句", warn: true },
    failed:      { text: "字幕或翻译失败，可点击右上角重试。", error: true },
    noSubtitles: { text: "这个视频没有可用字幕。" },
  };

  // 视频背景卡
  const BG_CARD = {
    meta: "全文分析完成 · 1:48:40 · 1333 句",
    summary: "Julian Treasure 在这場演讲中讨论「如何说话人们才愿意听」。他先指出说话不被听的常见原因，归纳出八卦、评判、消极、抱怨、借口、浮夸与固执七类习惯；随后给出让声音更有力量的四个基石（HAIL：诚实、真实、正直、爱），并演示音域、音色、语速与音量等声音工具的日常练习方法。",
    chapters: [
      { t: "00:00", title: "开场：为什么没人听你说话", start: 0 },
      { t: "01:12", title: "说话七宗罪", start: 72 },
      { t: "04:35", title: "HAIL：有力表达的四个基石", start: 275 },
      { t: "06:40", title: "声音工具箱：音域、音色与节奏", start: 400 },
      { t: "08:52", title: "总结：有意识地说，有意识地听", start: 532 },
    ],
    domain: { title: "领域与表达风格", body: "公共演讲 / 沟通技巧 · 语气亲和、例证生活化，含少量英式幽默；词汇整体常见，语速中等，适合跟读。" },
    people: { title: "人物与机构", count: 3, items: ["Julian Treasure（朱利安·特雷热，演讲者）", "TED（演讲平台）", "The Sound Agency（演讲者创立的声音咨询公司）"] },
    terms: { title: "术语表", count: 4, items: ["HAIL — 诚实 / 真实 / 正直 / 爱", "register — 音域", "timbre — 音色", "prosody — 韵律"] },
    issues: { title: "疑似识别问题", count: 2, items: ["02:14 “HAIL” 被识别为 “hale”，已按上下文修正", "07:31 “prosody” 识别置信度较低，翻译时按音韵学处理"] },
    footer: "背景卡仅用于帮助模型理解全局语境；原句与相邻字幕始终具有更高优先级。",
  };

  // 配色预设（英文 + 中文双字体颜色）
  const COLOR_PRESETS = [
    { name: "经典白 / 黄", en: "#FFFFFF", zh: "#FFD54F" },
    { name: "统一高对比白", en: "#FFFFFF", zh: "#FFFFFF" },
    { name: "柔和白 / 青", en: "#F7F7F7", zh: "#7FDBFF" },
    { name: "暖白 / 橙",   en: "#FFF8E7", zh: "#FFB74D" },
  ];

  function fmtTime(sec) {
    const m = Math.floor(sec / 60), s = Math.floor(sec % 60);
    return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
  }

  function currentSubtitleAt(t) {
    let cur = SUBTITLES[0];
    for (const s of SUBTITLES) { if (t >= s.start) cur = s; else break; }
    return cur;
  }

  function thumbStyle(video) {
    const [h, s, l] = video.hue;
    return {
      background:
        `radial-gradient(90px 50px at 30% 25%, hsla(${h},${s}%,${l + 22}%,0.9), transparent 70%),` +
        `linear-gradient(150deg, hsl(${h},${s}%,${l}%), hsl(${h + 26},${s - 8}%,${l - 20}%))`,
    };
  }

  Object.assign(window, {
    STATUS, VIDEOS, HIDDEN_VIDEOS, SUBTITLES, subtitlesPartial,
    PHASE_FOOTER, BG_CARD, COLOR_PRESETS,
    GLOSS_MAP, VOCAB_DETAIL, VOCAB_LIST,
    fmtTime, currentSubtitleAt, thumbStyle,
  });
})();
