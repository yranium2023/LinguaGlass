import { useEffect, useState } from "react";
import type { ViewState } from "./protocol";
import { advanceReading, emptyReading } from "./subtitle";
export function useSubtitle(view: ViewState, seconds: number) {
  const [reading, setReading] = useState(emptyReading);
  useEffect(() => {
    const tick = () =>
      setReading((s) =>
        advanceReading(s, view.sessionId, view.rows, Date.now(), seconds),
      );
    tick();
    const timer = setInterval(tick, 250);
    return () => clearInterval(timer);
  }, [view.sessionId, view.rows, seconds]);
  return reading.session === view.sessionId ? reading.row : undefined;
}
