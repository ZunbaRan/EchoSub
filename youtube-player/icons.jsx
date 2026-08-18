/* icons.jsx — SF Symbols 风格的线性图标集（stroke 1.6，圆角端点） */
(function () {
  const I = ({ size = 14, children, style }) => (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
         stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
         style={style} aria-hidden="true">{children}</svg>
  );

  const IconLink = (p) => (
    <I {...p}><path d="M8.2 11.8a3.5 3.5 0 0 0 5 0l2.4-2.4a3.54 3.54 0 0 0-5-5l-1.1 1.1" />
      <path d="M11.8 8.2a3.5 3.5 0 0 0-5 0L4.4 10.6a3.54 3.54 0 0 0 5 5l1.1-1.1" /></I>
  );
  const IconPlus = (p) => (<I {...p}><path d="M10 4.5v11M4.5 10h11" /></I>);
  const IconPlay = (p) => (<I {...p}><path d="M6.5 4.8v10.4a.6.6 0 0 0 .92.5l8.2-5.2a.6.6 0 0 0 0-1L7.42 4.3a.6.6 0 0 0-.92.5Z" fill="currentColor" stroke="none" /></I>);
  const IconPause = (p) => (<I {...p}><path d="M6 4.5h2.6v11H6zM11.4 4.5H14v11h-2.6z" fill="currentColor" stroke="none" /></I>);
  const IconBack5 = (p) => (
    <I {...p}><path d="M4.6 8.5A6.2 6.2 0 1 1 3.8 12" /><path d="M4 5v3.6h3.6" />
      <text x="10" y="13.2" textAnchor="middle" fontSize="6.4" fill="currentColor" stroke="none" fontWeight="700">5</text></I>
  );
  const IconFwd5 = (p) => (
    <I {...p}><path d="M15.4 8.5A6.2 6.2 0 1 0 16.2 12" /><path d="M16 5v3.6h-3.6" />
      <text x="10" y="13.2" textAnchor="middle" fontSize="6.4" fill="currentColor" stroke="none" fontWeight="700">5</text></I>
  );
  const IconPin = (p) => (<I {...p}><path d="M11.5 3.5 16.5 8.5l-3.2.8-2 2-.8 3.2-3.6-3.6M7 9.5 3.5 13" /></I>);
  const IconPinFill = (p) => (
    <I {...p}><path d="M11.5 3.5 16.5 8.5l-3.2.8-2 2-.8 3.2-3.6-3.6 4.6-4.7Z" fill="currentColor" stroke="none" />
      <path d="M7 9.5 3.5 13" /></I>
  );
  const IconSidebar = (p) => (<I {...p}><rect x="3" y="4" width="14" height="12" rx="2.5" /><path d="M8.2 4v12" /></I>);
  const IconLyrics = (p) => (<I {...p}><path d="M4 6.5h12M4 10h12M4 13.5h7" /><circle cx="16" cy="14" r="1.8" /><path d="M17.8 14V9.8" /></I>);
  const IconFloatWin = (p) => (<I {...p}><rect x="3" y="4.5" width="14" height="11" rx="2.5" /><rect x="7.5" y="8.5" width="8" height="6" rx="1.5" fill="currentColor" stroke="none" opacity="0.85" /></I>);
  const IconGear = (p) => (
    <I {...p}><circle cx="10" cy="10" r="2.4" />
      <path d="M10 3.2v1.9M10 14.9v1.9M3.2 10h1.9M14.9 10h1.9M5.2 5.2l1.3 1.3M13.5 13.5l1.3 1.3M14.8 5.2l-1.3 1.3M6.5 13.5l-1.3 1.3" /></I>
  );
  const IconExternal = (p) => (<I {...p}><path d="M8 5H5.5A1.5 1.5 0 0 0 4 6.5v8A1.5 1.5 0 0 0 5.5 16h8a1.5 1.5 0 0 0 1.5-1.5V12" /><path d="M11.5 4H16v4.5M16 4l-6.5 6.5" /></I>);
  const IconMore = (p) => (<I {...p}><circle cx="5" cy="10" r="1.3" fill="currentColor" stroke="none" /><circle cx="10" cy="10" r="1.3" fill="currentColor" stroke="none" /><circle cx="15" cy="10" r="1.3" fill="currentColor" stroke="none" /></I>);
  const IconCheck = (p) => (<I {...p}><path d="M4.5 10.5 8.5 14.5 15.5 6" /></I>);
  const IconRefresh = (p) => (<I {...p}><path d="M16 10a6 6 0 1 1-1.7-4.2M16 3.4v3h-3" /></I>);
  const IconX = (p) => (<I {...p}><path d="M5.5 5.5l9 9M14.5 5.5l-9 9" /></I>);
  const IconAlert = (p) => (<I {...p}><path d="M10 3.6 17 16H3L10 3.6Z" /><path d="M10 8v3.4" /><circle cx="10" cy="13.8" r="0.9" fill="currentColor" stroke="none" /></I>);
  const IconChevronD = (p) => (<I {...p}><path d="M5.5 8 10 12.5 14.5 8" /></I>);
  const IconTranslate = (p) => (<I {...p}><path d="M3.5 5.5h8M7.5 3.5v2M5.5 5.5c0 3 2 5.8 4.8 7M9.7 5.5c0 3-2 5.8-4.9 7" /><path d="M11.5 16.5 14 9.5l2.6 7M12.4 14.2h3.4" /></I>);
  const IconTextSize = (p) => (<I {...p}><path d="M3 15.5 6.4 6l3.4 9.5M4.2 12.2h4.4" /><path d="M11.5 15.5 14.6 8l3.1 7.5M12.6 13.2h4" /></I>);
  const IconFollow = (p) => (<I {...p}><path d="M10 3.5v3M10 13.5v3" /><path d="M6.5 6.5 10 10l3.5-3.5M6.5 13.5 10 10l3.5 3.5" /></I>);
  const IconLock = (p) => (<I {...p}><rect x="5" y="9" width="10" height="7.5" rx="1.8" /><path d="M7 9V7a3 3 0 0 1 6 0v2" /></I>);
  const IconUnlock = (p) => (<I {...p}><rect x="5" y="9" width="10" height="7.5" rx="1.8" /><path d="M7 9V7a3 3 0 0 1 5.8-1.1" /></I>);
  const IconCaptions = (p) => (<I {...p}><rect x="3" y="4.5" width="14" height="11" rx="2.5" /><path d="M5.8 9.5h3.4M5.8 12h5M12.4 9.5h1.8M12.4 12h1.8" strokeWidth="1.4" /></I>);
  const IconYoutube = (p) => (
    <I {...p}><rect x="2.8" y="5" width="14.4" height="10" rx="2.8" />
      <path d="M8.6 8.1v3.8l3.4-1.9-3.4-1.9Z" fill="currentColor" stroke="none" /></I>
  );
  const IconClipboard = (p) => (<I {...p}><rect x="5" y="4" width="10" height="13" rx="2" /><path d="M8 4.5V3.4A1.4 1.4 0 0 1 9.4 2h1.2A1.4 1.4 0 0 1 12 3.4v1.1" /></I>);
  const IconPaste = (p) => (<I {...p}><rect x="4.5" y="4" width="11" height="13" rx="2" /><path d="M7.5 4.5V3.2A1.2 1.2 0 0 1 8.7 2h2.6a1.2 1.2 0 0 1 1.2 1.2v1.3" /><path d="M7.5 9h5M7.5 12h5" strokeWidth="1.4" /></I>);
  const IconEye = (p) => (<I {...p}><path d="M2.5 10S5.5 5 10 5s7.5 5 7.5 5-3 5-7.5 5-7.5-5-7.5-5Z" /><circle cx="10" cy="10" r="2.2" /></I>);
  const IconTrash = (p) => (<I {...p}><path d="M4 6h12M8.5 6V4.5A1 1 0 0 1 9.5 3.5h1a1 1 0 0 1 1 1V6M6 6l.7 9.2A1.5 1.5 0 0 0 8.2 16.5h3.6a1.5 1.5 0 0 0 1.5-1.3L14 6" /></I>);
  const IconKey = (p) => (<I {...p}><circle cx="6.5" cy="10" r="3" /><path d="M9.5 10H17M14.5 10v2.5M17 10v2" /></I>);
  const IconDisplay = (p) => (<I {...p}><rect x="3" y="4" width="14" height="9.5" rx="1.8" /><path d="M8 16.5h4M10 13.5v3" /></I>);
  const IconClock = (p) => (<I {...p}><circle cx="10" cy="10" r="6.6" /><path d="M10 6.4V10l2.6 1.8" /></I>);
  const IconRepeat = (p) => (<I {...p}><path d="M13.5 3.5 17 7l-3.5 3.5" /><path d="M17 7H6a3 3 0 0 0-3 3v1" /><path d="M6.5 16.5 3 13l3.5-3.5" /><path d="M3 13h11a3 3 0 0 0 3-3V9" /></I>);
  const IconRepeat1 = (p) => (<I {...p}><path d="M13.5 3.5 17 7l-3.5 3.5" /><path d="M17 7H6a3 3 0 0 0-3 3v1" /><path d="M6.5 16.5 3 13l3.5-3.5" /><path d="M3 13h11a3 3 0 0 0 3-3V9" /><text x="10" y="12.4" textAnchor="middle" fontSize="6.5" fill="currentColor" stroke="none" fontWeight="700">1</text></I>);
  const IconExpand = (p) => (<I {...p}><path d="M11.5 4H16v4.5M16 4l-5.5 5.5M8.5 16H4v-4.5M4 16l5.5-5.5" /></I>);
  const IconSparkle = (p) => (<I {...p}><path d="M10 3.5 11.6 8 16 9.6 11.6 11.2 10 15.7 8.4 11.2 4 9.6 8.4 8 10 3.5Z" /><path d="M15.5 13.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8.8-2Z" strokeWidth="1.2" /></I>);
  const IconFolder = (p) => (<I {...p}><path d="M3 6.5A1.5 1.5 0 0 1 4.5 5h3L9 6.5h6.5A1.5 1.5 0 0 1 17 8v6.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 14.5v-8Z" /></I>);
  const IconTerminal = (p) => (<I {...p}><rect x="3" y="4" width="14" height="12" rx="2" /><path d="M6.5 8.5 9 11l-2.5 2.5M10.5 13.5H14" /></I>);
  const IconOpacity = (p) => (<I {...p}><circle cx="10" cy="10" r="6.6" /><path d="M10 3.4a6.6 6.6 0 0 1 0 13.2V3.4Z" fill="currentColor" stroke="none" /></I>);
  const IconEyeOff = (p) => (<I {...p}><path d="M4 4l12 12" /><path d="M7.5 5.8A8.9 8.9 0 0 1 10 5c4.5 0 7.5 5 7.5 5a13.6 13.6 0 0 1-2.3 2.9M12.5 14.2c-.8.5-1.6.8-2.5.8-4.5 0-7.5-5-7.5-5a13.4 13.4 0 0 1 2.6-3" /><path d="M8.3 8.4a2.2 2.2 0 0 0 3.1 3.1" /></I>);
  const IconRestore = (p) => (<I {...p}><path d="M4 8.5A6 6 0 1 1 5.7 13" /><path d="M4 4v4.5h4.5" /></I>);
  const IconDocText = (p) => (<I {...p}><path d="M6 3.5h5.5L15 7v9.5a1.5 1.5 0 0 1-1.5 1.5h-7A1.5 1.5 0 0 1 5 16.5v-11A1.5 1.5 0 0 1 6.5 3.5Z" /><path d="M11 3.5V7h4" /><path d="M7.5 10.5h5M7.5 13.5h5" strokeWidth="1.3" /></I>);

  Object.assign(window, {
    I,
    IconLink, IconPlus, IconPlay, IconPause, IconBack5, IconFwd5,
    IconPin, IconPinFill, IconSidebar, IconLyrics, IconFloatWin, IconGear,
    IconExternal, IconMore, IconCheck, IconRefresh, IconX, IconAlert,
    IconChevronD, IconTranslate, IconTextSize, IconFollow, IconLock, IconUnlock,
    IconCaptions, IconYoutube, IconClipboard, IconPaste, IconEye, IconTrash,
    IconKey, IconDisplay, IconClock, IconRepeat, IconRepeat1, IconExpand,
    IconSparkle, IconFolder, IconTerminal, IconOpacity, IconEyeOff,
    IconRestore, IconDocText,
  });
})();
