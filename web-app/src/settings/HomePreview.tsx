import { HourWheel } from "@site/hour-wheel.js";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import type { HourSelectionView } from "@/app/appearanceState.ts";
import type { OfficeHour } from "@/core/models.ts";
import { homeSkyProperties } from "@/home/ambientSky.ts";
import { SundialLayout } from "@/home/sundial.ts";
import { SundialView } from "@/home/SundialView.tsx";

/**
 * The Home a preview stands for, in its own points: a phone's width, and
 * the height of the Wheel's upper half with its pointer and a little sky
 * above. The Wheel is set as Home sets it on a phone, its hub at the foot
 * (`.home--wheel`). The Dial is laid out at its least height and as wide as
 * that makes the preview, so that its shadow comes in from the edge as it
 * does on Home.
 */
const homeWidth = 390;
const homeHeight = 300;
const dialWidth = (SundialLayout.minimumHeight * homeWidth) / homeHeight;

const noop = () => {};

/**
 * One of the two displays as Home shows it, drawn by Home's own Dial and
 * Wheel at a phone's size and made small, after the native app's live
 * previews (`LiveHourDisplayPreview`). It is a picture: nothing in it can be
 * reached or pressed.
 */
export function HomePreview({
  view,
  dark,
  sky,
  hour,
  rotation,
}: {
  view: HourSelectionView;
  dark: boolean;
  /** The sky of the hour lies behind it, in the Dynamic appearance. */
  sky: boolean;
  hour: OfficeHour;
  /** Where the Wheel stands. */
  rotation: number;
}) {
  const frame = useRef<HTMLSpanElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const measure = () => setWidth(element.getBoundingClientRect().width);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const className = [
    "home-preview",
    `home-preview--${view === "wheel" ? "wheel" : "dial"}`,
    dark ? "theme-dark" : "theme-light",
  ].join(" ");
  // The Wheel takes the sky of horarum.com at its own angle; the Dial the
  // quieter sky of the hour, as each does on Home.
  const style =
    sky && view === "wheel"
      ? (homeSkyProperties(rotation) as CSSProperties)
      : undefined;
  return (
    <span
      ref={frame}
      className={className}
      style={style}
      data-sky={sky && view !== "wheel" ? hour : undefined}
      aria-hidden="true"
      inert
    >
      {sky && <span className="home-preview__sky" />}
      {view === "wheel" ? (
        <WheelPreview hour={hour} rotation={rotation} dark={dark} />
      ) : (
        width > 0 && (
          <span
            className="home-preview__dial"
            style={{
              width: dialWidth,
              height: SundialLayout.minimumHeight,
              transform: `translateX(-50%) scale(${width / dialWidth})`,
            }}
          >
            <SundialView
              width={dialWidth}
              height={SundialLayout.minimumHeight}
              selection={hour}
              followsLocalTime
              showsShadow={!dark}
              onSelect={noop}
              onLiveHourChange={noop}
              onOpenOffice={noop}
            />
          </span>
        )
      )}
    </span>
  );
}

/** The Wheel, drawn by the site's own painter, still at `rotation`. */
function WheelPreview({
  hour,
  rotation,
  dark,
}: {
  hour: OfficeHour;
  rotation: number;
  dark: boolean;
}) {
  const stage = useRef<HTMLSpanElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const wheel = useRef<HourWheel | null>(null);

  useEffect(() => {
    if (!stage.current || !canvas.current) return;
    const created = new HourWheel(canvas.current, {
      tapestrySource: "/wheel/tapestry.webp",
    });
    wheel.current = created;
    // The painter draws for the size its stage has on the page.
    const observer = new ResizeObserver(() => created.resize());
    observer.observe(stage.current);
    void created.ready.then(() => created.resize());
    return () => {
      observer.disconnect();
      wheel.current = null;
    };
  }, []);

  useEffect(() => {
    wheel.current?.setState({
      rotation,
      selectedID: hour,
      appearanceBlend: dark ? 1 : 0,
    });
  }, [dark, hour, rotation]);

  return (
    <>
      <span ref={stage} className="home-preview__wheel">
        <canvas ref={canvas} />
      </span>
      <span className="home-preview__pointer" />
    </>
  );
}
