import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { useAppModel, useAppState, useServices } from "@/app/context.tsx";
import { Sheet } from "@/components/Sheet.tsx";
import {
  LocalDays,
  ObservanceTitle,
  Ranks,
  type LocalDay,
} from "@/core/models.ts";
import type { CalendarDay } from "@/data/corpus.ts";

const monthTitle = new Intl.DateTimeFormat("en-US", {
  month: "long",
  year: "numeric",
});
const monthName = new Intl.DateTimeFormat("en-US", { month: "long" });
const weekdayAbbreviation = new Intl.DateTimeFormat("en-US", {
  weekday: "short",
});
const spokenDate = new Intl.DateTimeFormat("en-US", {
  weekday: "long",
  month: "long",
  day: "numeric",
});
const fullDate = new Intl.DateTimeFormat("en-US", {
  weekday: "long",
  month: "long",
  day: "numeric",
  year: "numeric",
});

interface Month {
  readonly year: number;
  /** Counting from one. */
  readonly month: number;
}

function monthOf(day: LocalDay): Month {
  return { year: day.year, month: day.month };
}

function adding(month: Month, offset: number): Month {
  const date = new Date(month.year, month.month - 1 + offset, 1);
  return { year: date.getFullYear(), month: date.getMonth() + 1 };
}

function firstDay(month: Month): LocalDay {
  return LocalDays.make(month.year, month.month, 1);
}

function lastDay(month: Month): LocalDay {
  return LocalDays.fromDate(new Date(month.year, month.month, 0));
}

function intersects(
  month: Month,
  coverage: { start: LocalDay; end: LocalDay } | null,
): boolean {
  if (!coverage) return false;
  return (
    LocalDays.compare(lastDay(month), coverage.start) >= 0 &&
    LocalDays.compare(firstDay(month), coverage.end) <= 0
  );
}

function sameMonth(a: Month, b: Month): boolean {
  return a.year === b.year && a.month === b.month;
}

function markers(isSelected: boolean, isToday: boolean): string | undefined {
  const values = [
    isSelected ? "Selected" : null,
    isToday ? "Today" : null,
  ].filter(Boolean);
  return values.length ? values.join(", ") : undefined;
}

function MonthList({
  month,
  onChoose,
  onChangeMonth,
}: {
  month: Month;
  onChoose: (day: LocalDay) => void;
  onChangeMonth: (month: Month) => void;
}) {
  const { corpus } = useServices();
  const state = useAppState();
  const [days, setDays] = useState<readonly CalendarDay[] | null>(null);
  const [failed, setFailed] = useState(false);
  const selectedRow = useRef<HTMLLIElement>(null);
  const selected = state.selectedDay?.date ?? state.selectedCivilDate;
  const today = LocalDays.fromDate(new Date());

  useEffect(() => {
    let cancelled = false;
    setDays(null);
    setFailed(false);
    corpus
      .daysInMonth(state.officeTradition, month.year, month.month)
      .then((loaded) => {
        if (!cancelled) setDays(loaded);
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [corpus, month.month, month.year, state.officeTradition]);

  // Bring the selected day to the middle of the list.
  useEffect(() => {
    if (!days) return;
    const timer = window.setTimeout(() => {
      selectedRow.current?.scrollIntoView({ block: "center" });
    }, 120);
    return () => window.clearTimeout(timer);
  }, [days]);

  const previous = adding(month, -1);
  const next = adding(month, 1);

  return (
    <div className="month-days">
      <button
        type="button"
        className="month-days__neighbour"
        disabled={!intersects(previous, state.coverage)}
        onClick={() => onChangeMonth(previous)}
      >
        <ChevronLeft aria-hidden="true" />
        {monthName.format(LocalDays.date(firstDay(previous)))}
      </button>

      {failed ? (
        <p className="month-days__status" role="alert">
          This month could not be loaded.
        </p>
      ) : days === null ? (
        <p className="month-days__status" role="status">
          <span className="spinner" />
        </p>
      ) : (
        <ul>
          {days.map((day) => {
            const date = LocalDays.date(day.date);
            const isSelected = LocalDays.equals(day.date, selected);
            const isToday = LocalDays.equals(day.date, today);
            const rank = Ranks.rankLabel(day);
            const title = ObservanceTitle.latin(day.titleLatin);
            return (
              <li
                key={LocalDays.description(day.date)}
                ref={isSelected ? selectedRow : undefined}
              >
                <button
                  type="button"
                  className={[
                    "month-day",
                    isSelected ? "month-day--selected" : "",
                    isToday ? "month-day--today" : "",
                  ].join(" ")}
                  aria-label={[spokenDate.format(date), rank, title]
                    .filter(Boolean)
                    .join(", ")}
                  aria-description={markers(isSelected, isToday)}
                  aria-current={isSelected ? "date" : undefined}
                  onClick={() => onChoose(day.date)}
                >
                  <span className="month-day__date" aria-hidden="true">
                    <span>{weekdayAbbreviation.format(date)}</span>
                    <span>{day.date.day}</span>
                  </span>
                  <span className="month-day__text" aria-hidden="true">
                    {rank && <span className="month-day__rank">{rank}</span>}
                    <span className="month-day__title" lang="la">
                      {title}
                    </span>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}

      <button
        type="button"
        className="month-days__neighbour"
        disabled={!intersects(next, state.coverage)}
        onClick={() => onChangeMonth(next)}
      >
        {monthName.format(LocalDays.date(firstDay(next)))}
        <ChevronRight aria-hidden="true" />
      </button>
    </div>
  );
}

function CalendarGrid({
  month,
  onChoose,
  onChangeMonth,
}: {
  month: Month;
  onChoose: (day: LocalDay) => void;
  onChangeMonth: (month: Month) => void;
}) {
  const state = useAppState();
  const selected = state.selectedDay?.date ?? state.selectedCivilDate;
  const today = LocalDays.fromDate(new Date());
  const coverage = state.coverage;

  const cells = useMemo(() => {
    const leading = LocalDays.date(firstDay(month)).getDay();
    const count = lastDay(month).day;
    const result: Array<LocalDay | null> = [];
    for (let index = 0; index < 42; index += 1) {
      const day = index - leading + 1;
      result.push(
        day >= 1 && day <= count
          ? LocalDays.make(month.year, month.month, day)
          : null,
      );
    }
    return result;
  }, [month]);

  const inRange = (day: LocalDay) =>
    coverage !== null &&
    LocalDays.compare(day, coverage.start) >= 0 &&
    LocalDays.compare(day, coverage.end) <= 0;
  const previous = adding(month, -1);
  const next = adding(month, 1);

  return (
    <div className="calendar-grid">
      <div className="calendar-grid__header">
        <button
          type="button"
          className="icon-button"
          aria-label="Previous month"
          disabled={!intersects(previous, coverage)}
          onClick={() => onChangeMonth(previous)}
        >
          <ChevronLeft aria-hidden="true" />
        </button>
        <p aria-live="polite">
          {monthTitle.format(LocalDays.date(firstDay(month)))}
        </p>
        <button
          type="button"
          className="icon-button"
          aria-label="Next month"
          disabled={!intersects(next, coverage)}
          onClick={() => onChangeMonth(next)}
        >
          <ChevronRight aria-hidden="true" />
        </button>
      </div>
      <div className="calendar-grid__weekdays" aria-hidden="true">
        {["S", "M", "T", "W", "T", "F", "S"].map((symbol, index) => (
          <span key={index}>{symbol}</span>
        ))}
      </div>
      <div className="calendar-grid__days">
        {cells.map((day, index) => {
          if (!day) return <span key={index} />;
          const isSelected = LocalDays.equals(day, selected);
          const isToday = LocalDays.equals(day, today);
          return (
            <button
              key={index}
              type="button"
              className={[
                "calendar-day",
                isSelected ? "calendar-day--selected" : "",
                isToday ? "calendar-day--today" : "",
              ].join(" ")}
              disabled={!inRange(day)}
              aria-label={fullDate.format(LocalDays.date(day))}
              aria-description={markers(isSelected, isToday)}
              aria-pressed={isSelected}
              onClick={() => onChoose(day)}
            >
              {day.day}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export interface MonthDaysSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * The offices of a month: each day with its class and feast, and, behind the
 * calendar button, a grid for reaching any date in the edition.
 */
export function MonthDaysSheet({ open, onOpenChange }: MonthDaysSheetProps) {
  const model = useAppModel();
  const state = useAppState();
  const selected = state.selectedDay?.date ?? state.selectedCivilDate;
  const [month, setMonth] = useState<Month>(() => monthOf(selected));
  const [showsGrid, setShowsGrid] = useState(false);
  const today = LocalDays.fromDate(new Date());

  // Each opening begins at the selected day's month, on the list.
  useEffect(() => {
    if (open) {
      setMonth(monthOf(selected));
      setShowsGrid(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const title = showsGrid
    ? "Calendar"
    : monthTitle.format(LocalDays.date(firstDay(month)));
  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title={title}
      detent="medium"
      closeLabel="Close Calendar"
      leading={
        showsGrid ? (
          <button
            type="button"
            className="icon-button"
            aria-label="Offices for this month"
            onClick={() => setShowsGrid(false)}
          >
            <ChevronLeft aria-hidden="true" />
          </button>
        ) : (
          <button
            type="button"
            className="icon-button"
            aria-label="Calendar"
            title="Choose any date"
            onClick={() => setShowsGrid(true)}
          >
            <CalendarDays aria-hidden="true" />
          </button>
        )
      }
    >
      {showsGrid ? (
        <>
          <CalendarGrid
            month={month}
            onChangeMonth={setMonth}
            onChoose={(day) => {
              // The grid stays open: a date chosen here may be only the first of several.
              setMonth(monthOf(day));
              void model.selectCivilDate(day);
            }}
          />
          {!sameMonth(month, monthOf(today)) &&
            intersects(monthOf(today), state.coverage) && (
              <button
                type="button"
                className="calendar-grid__today"
                onClick={() => setMonth(monthOf(today))}
              >
                Today
              </button>
            )}
        </>
      ) : (
        <MonthList
          month={month}
          onChangeMonth={setMonth}
          onChoose={(day) => {
            void model.selectCivilDate(day);
            onOpenChange(false);
          }}
        />
      )}
    </Sheet>
  );
}
