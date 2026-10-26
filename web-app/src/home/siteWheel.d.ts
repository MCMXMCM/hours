// The hour wheel's drawing and physics, and the browsers its place allows
// for, are the public site's own modules (web/local-site), shared rather
// than copied so the two wheels cannot drift.

declare module "@site/hour-wheel.js" {
  export interface HourWheelOptions {
    artworkExtent?: number;
    labelRadius?: number;
    labelScale?: number;
    selectedLabelRadius?: number;
    selectedLabelScale?: number;
    tapestrySource?: string;
    wheelScale?: number;
  }

  export class HourWheel {
    constructor(canvas: HTMLCanvasElement, options?: HourWheelOptions);
    readonly ready: Promise<void>;
    rotation: number;
    selectedID: string;
    resize(): void;
    draw(): void;
    targetRotation(id: string, reference?: number): number;
    hourAtPoint(clientX: number, clientY: number): string | null;
    setState(state: {
      rotation?: number;
      selectedID?: string;
      appearanceBlend?: number;
    }): void;
  }

  export function isWheelNightOffice(id: string): boolean;
  export function shortestWheelTarget(id: string, reference: number): number;
  export function wheelAngleFor(id: string): number;
  export function wheelHourForRotation(rotation: number): string;
}

declare module "@site/mobile-browser-layout.js" {
  /**
   * Marks the document for iOS Safari or Brave, whose bars lie lower over
   * the page than they report, and says which was found.
   */
  export function applyMobileWheelBrowserClass(
    navigatorObject?: Navigator,
    root?: HTMLElement,
  ): Promise<string | null>;
}

declare module "@site/hour-wheel-physics.js" {
  export const minimumCoastVelocity: number;
  export const maximumCoastVelocity: number;
  export const springDuration: number;
  export function dragRotation(translation: number, diameter: number): number;
  export function releaseAngularVelocity(
    samples: ReadonlyArray<{ x: number; time: number }>,
    diameter: number,
  ): number;
  export function coastDuration(initialVelocity: number): number;
  export function coastRotation(
    start: number,
    initialVelocity: number,
    elapsed: number,
    duration: number,
  ): number;
  export function springRotation(
    start: number,
    target: number,
    elapsed: number,
  ): number;
}
