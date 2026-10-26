/** A rectangle as CoreGraphics gives one: an origin and a size. */
export interface CantorGuideRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

// `CGRect.minY`, `maxY`, and `height` are those of the standardized
// rectangle, whose height is never negative.

function minY(rect: CantorGuideRect): number {
  return rect.height < 0 ? rect.y + rect.height : rect.y;
}

function maxY(rect: CantorGuideRect): number {
  return rect.height < 0 ? rect.y : rect.y + rect.height;
}

function height(rect: CantorGuideRect): number {
  return Math.abs(rect.height);
}

export const CantorGuideHighlightScope = {
  isActive(
    sectionID: string,
    selectedSectionID: string | null | undefined,
  ): boolean {
    return selectedSectionID != null && sectionID === selectedSectionID;
  },
};

const bottomMargin = 24;

export const CantorGuideViewportTracking = {
  scrollAnchorY(
    activeFrame: CantorGuideRect,
    readerFrame: CantorGuideRect,
    obscuredBottomHeight: number,
  ): number | null {
    if (!(height(readerFrame) > 0)) return null;

    const visibleTop = minY(readerFrame);
    const visibleBottom =
      maxY(readerFrame) - Math.max(0, obscuredBottomHeight) - bottomMargin;
    if (!(visibleBottom > visibleTop)) return 0.5;

    const isVisible =
      minY(activeFrame) >= visibleTop && maxY(activeFrame) <= visibleBottom;
    if (isVisible) return null;

    const visibleCenter = (visibleTop + visibleBottom) / 2;
    return Math.min(
      1,
      Math.max(0, (visibleCenter - minY(readerFrame)) / height(readerFrame)),
    );
  },
};
