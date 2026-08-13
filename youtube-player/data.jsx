/* data.jsx — 演示数据：播放列表 + 语义分句后的双语字幕 */
(function () {
  // 缩略图：CSS 渐变占位（真实产品中为 YouTube 缩略图）
  const VIDEOS = [
    {
      id: "v1", current: true,
      title: "How to Speak So That People Want to Listen",
      channel: "TED", duration: "9:58", progress: 0.34,
      status: { kind: "ok", label: "双语" },
      hue: [216, 78, 52],
    },
    {
      id: "v2",
      title: "The Art of Slow Reading in a Fast World",
      channel: "The School of Life", duration: "12:41", progress: 0.82,
      status: { kind: "ok", label: "双语" },
      hue: [262, 46, 48],
    },
    {
      id: "v3",
      title: "Inside the Mind of a Master Procrastinator",
      channel: "TED", duration: "14:03", progress: 0,
      status: { kind: "busy", label: "翻译中" },
      hue: [174, 52, 40],
    },
    {
      id: "v4",
      title: "Why We Get Bored and What To Do About It",
      channel: "Veritasium", duration: "18:26", progress: 0,
      status: { kind: "warn", label: "无字幕" },
      hue: [28, 72, 48],
    },
    {
      id: "v5",
      title: "Designing for Calm Technology",
      channel: "NN/g", duration: "7:52", progress: 0.12,
      status: { kind: "err", label: "翻译失败" },
      hue: [340, 58, 50],
    },
  ];

  // 字幕单元：稳定 ID + 起止时间 + 英文原文 + 中文译文
  // 已按语义合并为 2~8 秒完整短句（非 YouTube 机器切片）
  const SUBTITLES = [
    { id: "s01", start: 0,   end: 4.2,  en: "The human voice is the instrument we all play.", zh: "人声是我们每个人都会演奏的乐器。" },
    { id: "s02", start: 4.2, end: 9.6,  en: "It's the most powerful sound in the world, probably.", zh: "它大概是世界上最有力量的声音。" },
    { id: "s03", start: 9.6, end: 15.8, en: "It's the only one that can start a war, or say \"I love you.\"", zh: "它是唯一能发动战争，也能说出“我爱你”的声音。" },
    { id: "s04", start: 15.8, end: 22.4, en: "And yet, many people have the experience that when they speak, people don't listen to them.", zh: "然而很多人都有这样的体会：自己说话时，别人并不在听。" },
    { id: "s05", start: 22.4, end: 28.9, en: "Why is that? How can we speak powerfully to make change in the world?", zh: "为什么会这样？我们怎样说话才有力量，才能推动改变？" },
    { id: "s06", start: 28.9, end: 35.1, en: "What I'd like to suggest is there are a number of habits we need to move away from.", zh: "我想说的是，有几个说话的习惯，我们需要戒掉。" },
    { id: "s07", start: 35.1, end: 41.3, en: "I've assembled for your pleasure here seven deadly sins of speaking.", zh: "我为大家总结了说话的七宗罪。" },
    { id: "s08", start: 41.3, end: 47.6, en: "I'm not pretending this is an exhaustive list, but these seven, I think, are pretty large habits that we can all fall into.", zh: "这并不是一份完整清单，但这七条，我认为是我们都容易犯的大毛病。" },
    { id: "s09", start: 47.6, end: 53.2, en: "First, gossip. Speaking ill of somebody who's not present.", zh: "第一，八卦。在背后说别人的闲话。" },
    { id: "s10", start: 53.2, end: 59.8, en: "Not a nice habit, and we know perfectly well the person gossiping will be gossiping about us five minutes later.", zh: "这不是好习惯，而且我们心里很清楚，说别人闲话的人，五分钟后就会说我们。" },
    { id: "s11", start: 59.8, end: 66.4, en: "Second, judging. It's very hard to listen to somebody if you know that you're being judged.", zh: "第二，评判。如果你知道自己正被评判，就很难再听对方说下去。" },
    { id: "s12", start: 66.4, end: 73.5, en: "Negativity is another one. It's very hard to listen when everybody's that negative.", zh: "消极也是其中之一。当所有人都那么消极时，倾听会变得很难。" },
    { id: "s13", start: 73.5, end: 80.2, en: "And another form of negativity, complaining. Well, this is the national art of the U.K.", zh: "还有一种消极形式是抱怨。嗯，这可以说是英国的“国粹”。" },
    { id: "s14", start: 80.2, end: 88.0, en: "It's what we do to pass the time, but actually, complaining is viral misery.", zh: "我们靠抱怨打发时间，可实际上，抱怨是会传染的痛苦。" },
  ];

  // 翻译进行中：可见区域之后保留少量待翻译句
  function subtitlesTranslating() {
    return SUBTITLES.map((s, i) => (i >= 8 ? { ...s, zh: null } : s));
  }

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

  Object.assign(window, { VIDEOS, SUBTITLES, subtitlesTranslating, fmtTime, currentSubtitleAt, thumbStyle });
})();
