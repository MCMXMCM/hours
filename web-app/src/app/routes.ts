import {
  LocalDays,
  OfficeHours,
  type LocalDay,
  type OfficeHour,
} from "@/core/models.ts";

/** The address of an office: `/office/2026-10-04/vespers`. */
export function officePath(day: LocalDay, hour: OfficeHour): string {
  return `/office/${LocalDays.description(day)}/${hour}`;
}

export function parseOfficeRoute(
  date: string | undefined,
  hour: string | undefined,
): { day: LocalDay; hour: OfficeHour } | null {
  const day = date ? LocalDays.fromISO(date) : null;
  if (!day || !OfficeHours.isOfficeHour(hour)) return null;
  // Reject a date the calendar does not have, such as February 30.
  if (!LocalDays.equals(LocalDays.fromDate(LocalDays.date(day)), day))
    return null;
  return { day, hour };
}

/** The office a path addresses, or null when it addresses none. */
export function officeAtPath(
  pathname: string,
): { day: LocalDay; hour: OfficeHour } | null {
  const match = /^\/office\/([^/]+)\/([^/]+)\/?$/i.exec(pathname);
  return match ? parseOfficeRoute(match[1], match[2]) : null;
}

/** The address of a day's Mass: `/mass/2026-10-25`, or `/mass/2026-12-25/2`
 * for the second of a day's Masses. */
export function massPath(day: LocalDay, index = 0): string {
  const date = LocalDays.description(day);
  return index > 0 ? `/mass/${date}/${index + 1}` : `/mass/${date}`;
}

export function parseMassRoute(
  date: string | undefined,
  number: string | undefined,
): { day: LocalDay; index: number } | null {
  const day = date ? LocalDays.fromISO(date) : null;
  if (!day) return null;
  if (!LocalDays.equals(LocalDays.fromDate(LocalDays.date(day)), day))
    return null;
  if (number === undefined) return { day, index: 0 };
  if (!/^[1-9]$/.test(number)) return null;
  return { day, index: Number(number) - 1 };
}
