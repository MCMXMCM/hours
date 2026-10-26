import { ChevronLeft } from "lucide-react";
import { forwardRef, type ReactNode } from "react";
import "./guides.css";

export interface GuideBarProps {
  /** The page's name, as a navigation bar shows it. */
  title: string;
  /** What the bar is called to assistive technology: the guide's name. */
  label: string;
  onBack: () => void;
  /** Controls at the trailing edge of the bar. */
  children?: ReactNode;
}

/**
 * The bar at the head of a page of a guide: the way back, the page's name,
 * and whatever the page offers beside it.
 */
export const GuideBar = forwardRef<HTMLElement, GuideBarProps>(
  function GuideBar({ title, label, onBack, children }, ref) {
    return (
      <nav ref={ref} className="guide-bar" aria-label={label}>
        <div>
          <button
            type="button"
            className="icon-button"
            aria-label="Back"
            onClick={onBack}
          >
            <ChevronLeft aria-hidden="true" />
          </button>
        </div>
        <p className="guide-bar__title">{title}</p>
        <div className="guide-bar__actions">{children}</div>
      </nav>
    );
  },
);
