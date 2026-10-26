import {
  Book,
  ChevronRight,
  Code,
  Globe,
  Heart,
  ListMusic,
  Mail,
  Package,
  Scale,
  ScrollText,
} from "lucide-react";
import { Link } from "react-router-dom";
import { Sheet } from "@/components/Sheet.tsx";
import { OfficeHours, officeHours } from "@/core/models.ts";

const contacts = [
  {
    title: "Website",
    value: "horarum.com",
    href: "https://horarum.com",
    icon: Globe,
  },
  {
    title: "Contribute",
    value: "horarum.com/support",
    href: "https://horarum.com/support",
    icon: Heart,
  },
  {
    title: "Email",
    value: "help@horarum.com",
    href: "mailto:help@horarum.com",
    icon: Mail,
  },
  {
    title: "Source Code",
    value: "MCMXMCM/hours",
    href: "https://github.com/MCMXMCM/hours",
    icon: Code,
  },
] as const;

/** The license, the source with its notices, and the notices of the
 * software the web app is built with. */
const notices = [
  {
    title: "License",
    value: "GNU GPL v3",
    href: "/GPL-3.0.txt",
    icon: Scale,
  },
  {
    title: "Notices",
    value: "NOTICE.md",
    href: "https://github.com/MCMXMCM/hours/blob/main/NOTICE.md",
    icon: ScrollText,
  },
  {
    title: "Third-party software",
    value: "licenses.txt",
    href: "/licenses.txt",
    icon: Package,
  },
] as const;

function About() {
  const currentHour = OfficeHours.current(new Date());
  const schedule = officeHours
    .map(
      (hour) =>
        `${OfficeHours.englishTitle(hour)}, ${OfficeHours.customaryTimeRange(hour)}`,
    )
    .join("; ");
  return (
    <div className="about">
      <p className="about__logo" role="img" aria-label="Hours">
        <img src="/icons/icon-192.png" alt="" />
        <span aria-hidden="true">OURS</span>
      </p>

      <table
        className="about__hours"
        aria-label={`Automatic hour schedule. ${schedule}. Current hour: ${OfficeHours.englishTitle(currentHour)}.`}
      >
        <tbody>
          {officeHours.map((hour) => (
            <tr
              key={hour}
              className={hour === currentHour ? "is-current" : undefined}
            >
              <th scope="row">{OfficeHours.englishTitle(hour)}</th>
              <td>{OfficeHours.customaryTimeRange(hour)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <ul className="about__guides">
        {guides.map(({ title, summary, to, icon: Icon }) => (
          <li key={to}>
            <Link to={to}>
              <Icon aria-hidden="true" />
              <span>
                <span className="about__guide-title">{title}</span>
                <span className="about__guide-summary">{summary}</span>
              </span>
              <ChevronRight aria-hidden="true" />
            </Link>
          </li>
        ))}
      </ul>

      <section className="settings__section" aria-labelledby="about-contact">
        <h3 id="about-contact">Contact</h3>
        <p className="settings__description">
          Have a question, found a bug, or have a suggestion?
        </p>
        <ul className="about__links">
          {contacts.map(({ title, value, href, icon: Icon }) => (
            <li key={title}>
              <a
                href={href}
                target={href.startsWith("mailto:") ? undefined : "_blank"}
                rel="noreferrer"
                aria-label={`${title}, ${value}`}
              >
                <Icon aria-hidden="true" />
                <span>{title}</span>
                <span>{value}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>

      <section className="settings__section" aria-labelledby="about-license">
        <h3 id="about-license">License</h3>
        <p className="settings__description">
          Hours is free software, copyright © 2026 Matthew McCarty. You may
          redistribute and modify it under the terms of the GNU General Public
          License, version 3 only. It comes with absolutely no warranty.
        </p>
        <p className="settings__description">
          Its chant includes transcriptions from the Nocturnale Romanum, the
          Vesperale Romanum, and the Antiphonale Romanum, published under the
          same license, which Hours has modified. Their editable source, and the
          changes made to them and when, are published with the source code.
        </p>
        <ul className="about__links">
          {notices.map(({ title, value, href, icon: Icon }) => (
            <li key={title}>
              <a
                href={href}
                target="_blank"
                rel="noreferrer"
                aria-label={`${title}, ${value}`}
              >
                <Icon aria-hidden="true" />
                <span>{title}</span>
                <span>{value}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

/** The two references About leads to, each a page of its own. */
const guides = [
  {
    title: "Guide to Chant",
    summary: "Learn to read, hear, and sing Gregorian chant",
    to: "/guides/chant",
    icon: ListMusic,
  },
  {
    title: "Rubrics",
    summary: "The order of the Office, its psalms, and its chant",
    to: "/guides/rubrics",
    icon: Book,
  },
] as const;

export interface AboutSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * About: the hours and their times, the two guides, where to write, and the
 * license with its notices.
 * It is opened from Home, by the information button beside Settings.
 */
export function AboutSheet({ open, onOpenChange }: AboutSheetProps) {
  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title="About"
      closeLabel="Close About"
    >
      <About />
    </Sheet>
  );
}
