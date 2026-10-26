import { Component, StrictMode, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { App } from "./App.tsx";
import { AppServicesProvider, createAppServices } from "./app/context.tsx";
import { keepComingDaysAtHand, registerServiceWorker } from "./app/offline.ts";
import "./styles.css";

class Boundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  render() {
    return this.state.failed ? (
      <main className="home__unloaded" role="alert">
        <h1>Something interrupted Hours.</h1>
        <p>Your settings are still on this device.</p>
        <button type="button" onClick={() => location.reload()}>
          Reload
        </button>
      </main>
    ) : (
      this.props.children
    );
  }
}

const services = createAppServices();
void registerServiceWorker();
keepComingDaysAtHand(services.model);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Boundary>
      <BrowserRouter>
        <AppServicesProvider services={services}>
          <App />
        </AppServicesProvider>
      </BrowserRouter>
    </Boundary>
  </StrictMode>,
);
