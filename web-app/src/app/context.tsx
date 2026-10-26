import { createContext, useContext, type ReactNode } from "react";
import { Corpus } from "@/data/corpus.ts";
import { AppModel, type AppState } from "./appModel.ts";
import { Appearance } from "./appearance.ts";
import { openingHour, type AppearanceState } from "./appearanceState.ts";
import { Preferences } from "./preferences.ts";
import { useStore } from "./store.ts";

export interface AppServices {
  readonly corpus: Corpus;
  readonly preferences: Preferences;
  readonly model: AppModel;
  readonly appearance: Appearance;
}

export function createAppServices(): AppServices {
  const corpus = new Corpus();
  const preferences = new Preferences();
  const model = new AppModel(corpus, preferences, undefined, location.pathname);
  return {
    corpus,
    preferences,
    model,
    appearance: new Appearance(
      preferences,
      openingHour(location.pathname, model.state.selectedHour),
    ),
  };
}

const ServicesContext = createContext<AppServices | null>(null);

export function AppServicesProvider({
  services,
  children,
}: {
  services: AppServices;
  children: ReactNode;
}) {
  return (
    <ServicesContext.Provider value={services}>
      {children}
    </ServicesContext.Provider>
  );
}

export function useServices(): AppServices {
  const services = useContext(ServicesContext);
  if (!services) throw new Error("AppServicesProvider is missing.");
  return services;
}

export function useAppModel(): AppModel {
  return useServices().model;
}

export function useAppState(): AppState {
  return useStore(useServices().model.store);
}

export function useAppearance(): AppearanceState {
  return useStore(useServices().appearance.store);
}
