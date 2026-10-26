import {
  isDark,
  isNightHour,
  type AppearanceMode,
  type HourSelectionView,
} from "@/app/appearanceState.ts";
import {
  useAppModel,
  useAppState,
  useAppearance,
  useServices,
} from "@/app/context.tsx";
import {
  OfficeTraditions,
  officeTraditions,
  type OfficeTradition,
} from "@/app/officeTradition.ts";
import { SegmentedControl } from "@/components/SegmentedControl.tsx";
import { Sheet } from "@/components/Sheet.tsx";
import { OfficeHours, type OfficeHour } from "@/core/models.ts";
import { openingWheelRotation } from "@/home/ambientSky.ts";
import { HomePreview } from "./HomePreview.tsx";

function Synchronize() {
  const model = useAppModel();
  const state = useAppState();
  const isAutomatic = state.automaticallySelectsCurrentOffice;
  return (
    <section
      className="settings__section"
      aria-labelledby="settings-synchronize"
    >
      <h3 id="settings-synchronize">Synchronize</h3>
      <SegmentedControl
        label="Synchronization"
        value={isAutomatic ? "automatic" : "manual"}
        options={[
          { value: "manual", title: "Manual" },
          { value: "automatic", title: "Automatic" },
        ]}
        onChange={(value) => {
          model.setAutomaticOfficeSelection(value === "automatic");
          // Returning to the clock returns to today and the present hour.
          if (value === "automatic") void model.selectCurrentOffice();
        }}
      />
      <p className="settings__description">
        {isAutomatic
          ? "Displaying the current canonical hour for your device’s current time."
          : "Select Automatic to synchronize and automatically keep the current hour displayed."}
      </p>
    </section>
  );
}

/**
 * The hour the previews show, and where the Wheel stands for it: the hour on
 * Home's screen, and the Wheel turning with the clock while Home follows it.
 */
function usePreviewHour(): { hour: OfficeHour; rotation: number } {
  const look = useAppearance();
  const state = useAppState();
  const now = new Date();
  const hour =
    look.displayedHour ?? state.selectedHour ?? OfficeHours.current(now);
  const rotation = openingWheelRotation(
    hour,
    state.automaticallySelectsCurrentOffice &&
      hour === OfficeHours.current(now),
    window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    now,
  );
  return { hour, rotation };
}

/** The two ways Home shows the hours, in the order the native app offers them. */
const hourSelectionViews: ReadonlyArray<{
  view: HourSelectionView;
  title: string;
}> = [
  { view: "sunDial", title: "Dial" },
  { view: "wheel", title: "Wheel" },
];

function DisplayChoice() {
  const { appearance } = useServices();
  const look = useAppearance();
  const { hour, rotation } = usePreviewHour();
  return (
    <section className="settings__section" aria-labelledby="settings-display">
      <h3 id="settings-display">Display</h3>
      <div className="settings__cards" role="radiogroup" aria-label="Display">
        {hourSelectionViews.map((option) => (
          <button
            key={option.view}
            type="button"
            role="radio"
            aria-checked={look.hourSelectionView === option.view}
            className="settings-card"
            onClick={() => appearance.setHourSelectionView(option.view)}
          >
            <span className="settings-card__preview">
              <HomePreview
                view={option.view}
                dark={isDark(look)}
                sky={look.mode === "dynamic"}
                hour={hour}
                rotation={rotation}
              />
            </span>
            <span className="settings-card__title">{option.title}</span>
          </button>
        ))}
      </div>
    </section>
  );
}

function AppearanceChoice() {
  const { appearance } = useServices();
  const look = useAppearance();
  const { hour, rotation } = usePreviewHour();
  const dynamicIsDark = isNightHour(hour);
  const cards: Array<{
    mode: AppearanceMode;
    title: string;
    subtitle: string;
    dark: boolean;
  }> = [
    {
      mode: "dynamic",
      title: "Dynamic",
      subtitle: dynamicIsDark ? "Dark for Night Hours" : "Light for Day Hours",
      dark: dynamicIsDark,
    },
    {
      mode: "system",
      title: "System",
      subtitle: `System is ${look.systemIsDark ? "Dark" : "Light"}`,
      dark: look.systemIsDark,
    },
  ];
  return (
    <section
      className="settings__section"
      aria-labelledby="settings-appearance"
    >
      <h3 id="settings-appearance">Appearance</h3>
      <div
        className="settings__cards"
        role="radiogroup"
        aria-label="Appearance"
      >
        {cards.map((card) => (
          <button
            key={card.mode}
            type="button"
            role="radio"
            aria-checked={look.mode === card.mode}
            className="settings-card"
            onClick={() => appearance.setMode(card.mode)}
          >
            <span className="settings-card__preview">
              <HomePreview
                view={look.hourSelectionView}
                dark={card.dark}
                sky={card.mode === "dynamic"}
                hour={hour}
                rotation={rotation}
              />
            </span>
            <span className="settings-card__title">{card.title}</span>
            <span className="settings-card__subtitle">{card.subtitle}</span>
          </button>
        ))}
      </div>
      <p className="settings__description">
        Dynamic follows the canonical hours. System follows your device’s
        current light or dark appearance.
      </p>
    </section>
  );
}

function Rubrics() {
  const model = useAppModel();
  const state = useAppState();
  const change = (tradition: OfficeTradition) =>
    void model.changeOfficeTradition(tradition);
  return (
    <section className="settings__section" aria-labelledby="settings-rubrics">
      <h3 id="settings-rubrics">
        Rubrics
        {state.isChangingTradition && (
          <span
            className="spinner spinner--small"
            role="status"
            aria-label="Changing office tradition"
          />
        )}
      </h3>
      <SegmentedControl
        label="Rubrics"
        value={state.officeTradition}
        options={officeTraditions.map((tradition) => ({
          value: tradition,
          title: OfficeTraditions.title(tradition),
        }))}
        disabled={state.isChangingTradition}
        onChange={change}
      />
      {state.traditionErrorMessage && (
        <p className="settings__error" role="alert">
          {state.traditionErrorMessage}
        </p>
      )}
      <p className="settings__description">
        {OfficeTraditions.description(state.officeTradition)}
      </p>
      {state.officeTradition !== "roman1960" && (
        <p className="settings__note">
          Source edition: Latin and English from Divinum Officium. Chant is
          included where it can be matched to the text; some passages are
          text-only. Independent liturgical and musical review is pending.
        </p>
      )}
    </section>
  );
}

export interface SettingsSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/** Settings: how the hour is chosen and shown, and the edition prayed. */
export function SettingsSheet({ open, onOpenChange }: SettingsSheetProps) {
  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title="Settings"
      closeLabel="Close Settings"
    >
      <div className="settings">
        <Synchronize />
        <DisplayChoice />
        <AppearanceChoice />
        <Rubrics />
      </div>
    </Sheet>
  );
}
