const alternateIOSBrowserPattern =
  /CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|GSA/i;

export function isIOSDevice(
  userAgent,
  platform = "",
  maxTouchPoints = 0,
) {
  return (
    /iPhone|iPad|iPod/i.test(userAgent) ||
    (platform === "MacIntel" && maxTouchPoints > 1)
  );
}

export function mobileWheelBrowserClass({
  userAgent,
  platform = "",
  maxTouchPoints = 0,
  isBrave = false,
}) {
  if (!isIOSDevice(userAgent, platform, maxTouchPoints)) return null;
  if (isBrave || /\bBrave\b/i.test(userAgent)) return "ios-brave";
  if (/Safari/i.test(userAgent) && !alternateIOSBrowserPattern.test(userAgent)) {
    return "ios-safari";
  }
  return null;
}

export async function applyMobileWheelBrowserClass(
  navigatorObject = navigator,
  root = document.documentElement,
) {
  const userAgent = navigatorObject.userAgent ?? "";
  const platform = navigatorObject.platform ?? "";
  const maxTouchPoints = navigatorObject.maxTouchPoints ?? 0;

  if (!isIOSDevice(userAgent, platform, maxTouchPoints)) return null;

  let isBrave = /\bBrave\b/i.test(userAgent);
  if (!isBrave && navigatorObject.brave?.isBrave) {
    try {
      isBrave = await navigatorObject.brave.isBrave();
    } catch {
      // Browser detection must never hold up or break the splash page.
    }
  }

  const className = mobileWheelBrowserClass({
    userAgent,
    platform,
    maxTouchPoints,
    isBrave,
  });
  if (className) root.classList.add(className);
  return className;
}
