import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./Dashboard";
import { Overlay } from "./Overlay";
import { loadPreferences } from "./preferences";
import "./flat.css";

const overlay = new URLSearchParams(location.search).get("overlay") === "1";
document.documentElement.dataset.surface = overlay ? "overlay" : "main";
const preferences = loadPreferences();
document.documentElement.dataset.theme = preferences.appearance.theme;
document.documentElement.dataset.size = preferences.appearance.size;
document.documentElement.dataset.accent = preferences.appearance.accent;
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>{overlay ? <Overlay /> : <App />}</React.StrictMode>,
);
