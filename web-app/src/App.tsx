import { lazy, Suspense } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { UpdatePrompt } from "./components/UpdatePrompt.tsx";
import { HomeScreen } from "./home/HomeScreen.tsx";

// The reader carries the engraver; Home does not wait for it.
const ReaderScreen = lazy(() => import("./reader/ReaderScreen.tsx"));
const MassScreen = lazy(() => import("./reader/MassScreen.tsx"));
// The two guides are fetched when one is first opened.
const ChantGuideScreen = lazy(() => import("./guides/ChantGuideScreen.tsx"));
const RubricsGuideScreen = lazy(
  () => import("./guides/RubricsGuideScreen.tsx"),
);

export function App() {
  return (
    <>
      <div className="ambient-sky" aria-hidden="true" />
      <Routes>
        <Route path="/" element={<HomeScreen />} />
        <Route
          path="/office/:date/:hour"
          element={
            <Suspense fallback={null}>
              <ReaderScreen />
            </Suspense>
          }
        />
        <Route
          path="/mass/:date/:number?"
          element={
            <Suspense fallback={null}>
              <MassScreen />
            </Suspense>
          }
        />
        <Route
          path="/guides/chant"
          element={
            <Suspense fallback={null}>
              <ChantGuideScreen />
            </Suspense>
          }
        />
        <Route
          path="/guides/rubrics"
          element={
            <Suspense fallback={null}>
              <RubricsGuideScreen />
            </Suspense>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <UpdatePrompt />
    </>
  );
}
