// The chant notation is parsed and engraved by the gabc-parser package
// (GABCParser, GABCLayout), whose types keep the names they had here. Hours
// imports them with HoursCore, and its timeline names a score's notes.
@_exported import GABCLayout
@_exported import GABCParser

extension ChantEvent: GregorianTimelineEvent {}

extension ChantTimeline: GregorianTimeline {}
