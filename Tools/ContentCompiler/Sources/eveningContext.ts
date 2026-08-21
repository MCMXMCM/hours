import { canonicalLiturgicalIdentity } from "./liturgicalIdentity.ts";
import type {
  CorpusInput,
  EveningContext,
  LiturgicalDay,
  OfficeDocument,
  OfficeObservance
} from "./types.ts";

function previousDate(date: string): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() - 1);
  return value.toISOString().slice(0, 10);
}

function identity(observance: { titleLatin: string }): string {
  return canonicalLiturgicalIdentity(observance.titleLatin);
}

function sameObservance(
  left: { titleLatin: string },
  right: { titleLatin: string }
): boolean {
  return identity(left) === identity(right);
}

function daytimeObservance(
  date: string,
  day: LiturgicalDay,
  officesByKey: ReadonlyMap<string, OfficeDocument>
): OfficeObservance | LiturgicalDay {
  return officesByKey.get(`${date}:matins`)?.observance
    ?? officesByKey.get(`${date}:lauds`)?.observance
    ?? day;
}

/**
 * Resolves Vespers once during compilation so the app never has to infer
 * precedence from ranks or adjacent civil dates at runtime.
 *
 * Explicit source labels take precedence. Otherwise, First Vespers belongs
 * to an observance other than the civil day's daytime office, and inferred
 * Second Vespers belongs to an observance that demonstrably began with First
 * Vespers. All remaining evening offices use the ordinary `ferialVespers`
 * display context ("Vespers"), including II- and III-class offices whose
 * celebration runs from Matins through Compline.
 */
export function withResolvedEveningContexts(
  input: CorpusInput
): CorpusInput {
  const daysByDate = new Map(
    input.days.map(day => [localDateKey(day), day])
  );
  const officesByKey = new Map(
    input.offices.map(office => [
      `${localDateKey(office)}:${office.hour}`,
      office
    ])
  );
  const contextsByDate = new Map<string, EveningContext>();
  const firstVespersIdentities = new Set<string>();

  for (const [date, day] of daysByDate) {
    const vespers = officesByKey.get(`${date}:vespers`);
    const observance = vespers?.observance;
    if (!vespers || !observance) {
      throw new Error(`Cannot resolve Vespers metadata for ${date}`);
    }

    const explicit = observance.eveningContext;
    if (explicit) {
      contextsByDate.set(date, explicit);
      if (explicit === "firstVespers") {
        firstVespersIdentities.add(identity(observance));
      }
      continue;
    }

    const daytime = daytimeObservance(date, day, officesByKey);
    if (!sameObservance(observance, daytime)) {
      contextsByDate.set(date, "firstVespers");
      firstVespersIdentities.add(identity(observance));
    }
  }

  for (const [date, day] of daysByDate) {
    if (contextsByDate.has(date)) continue;

    const vespers = officesByKey.get(`${date}:vespers`)!;
    const observance = vespers.observance!;
    const daytime = daytimeObservance(date, day, officesByKey);
    const precedingDate = previousDate(date);
    const precedingVespers = officesByKey.get(
      `${precedingDate}:vespers`
    );
    const followsOwnFirstVespers =
      contextsByDate.get(precedingDate) === "firstVespers"
      && Boolean(precedingVespers?.observance)
      && sameObservance(precedingVespers!.observance!, daytime);
    const hasFirstVespersElsewhere = firstVespersIdentities.has(
      identity(daytime)
    );

    contextsByDate.set(
      date,
      followsOwnFirstVespers || hasFirstVespersElsewhere
        ? "secondVespers"
        : "ferialVespers"
    );
  }

  const offices = input.offices.map(office => {
    if (office.hour !== "vespers" && office.hour !== "compline") {
      return office;
    }
    const date = localDateKey(office);
    const context = contextsByDate.get(date);
    const vespersObservance = officesByKey.get(
      `${date}:vespers`
    )?.observance;
    if (!context || !office.observance || !vespersObservance) {
      throw new Error(`Cannot apply evening metadata to ${date}:${office.hour}`);
    }
    if (!sameObservance(office.observance, vespersObservance)) {
      throw new Error(
        `${date}:${office.hour} does not belong to the resolved Vespers observance`
      );
    }
    return {
      ...office,
      observance: {
        ...office.observance,
        eveningContext: context
      }
    };
  });

  const days = input.days.map(day => ({
    ...day,
    eveningContext: contextsByDate.get(localDateKey(day))
  }));

  return { ...input, days, offices };
}

function localDateKey(value: LiturgicalDay | OfficeDocument): string {
  const { year, month, day } = value.date;
  return `${String(year).padStart(4, "0")}-`
    + `${String(month).padStart(2, "0")}-`
    + String(day).padStart(2, "0");
}
