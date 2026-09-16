import { Check, ChevronDown } from "lucide-react";
import { useEffect, useId, useMemo, useRef, useState } from "react";

export type GlassOption<T extends string | number> = {
  value: T;
  label: string;
  disabled?: boolean;
};

type Props<T extends string | number> = {
  value: T;
  options: GlassOption<T>[];
  onChange: (value: T) => void;
  ariaLabel: string;
  disabled?: boolean;
  compact?: boolean;
  id?: string;
};

export function GlassSelect<T extends string | number>({
  value,
  options,
  onChange,
  ariaLabel,
  disabled = false,
  compact = false,
  id,
}: Props<T>) {
  const generatedId = useId();
  const listId = `${id ?? generatedId}-listbox`;
  const root = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const selectedIndex = Math.max(
    0,
    options.findIndex((option) => option.value === value),
  );
  const [activeIndex, setActiveIndex] = useState(selectedIndex);
  const selected = options[selectedIndex] ?? options[0];
  const side = useMemo(() => {
    if (!open || !root.current) return "bottom";
    const rect = root.current.getBoundingClientRect();
    const menuHeight = Math.min(280, options.length * 44 + 12);
    return window.innerHeight - rect.bottom < menuHeight + 16 &&
      rect.top > menuHeight
      ? "top"
      : "bottom";
  }, [open, options.length]);

  useEffect(() => {
    if (!open) return;
    setActiveIndex(selectedIndex);
    const close = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open, selectedIndex]);

  function move(direction: 1 | -1) {
    let next = activeIndex;
    do {
      next = (next + direction + options.length) % options.length;
    } while (options[next]?.disabled && next !== activeIndex);
    setActiveIndex(next);
  }

  function choose(index: number) {
    const option = options[index];
    if (!option || option.disabled) return;
    onChange(option.value);
    setOpen(false);
  }

  return (
    <div
      className={`glass-select ${compact ? "compact" : ""}`}
      data-open={open}
      data-side={side}
      ref={root}
    >
      <button
        id={id}
        type="button"
        className="glass-select-trigger"
        role="combobox"
        aria-label={ariaLabel}
        aria-controls={listId}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-activedescendant={open ? `${listId}-${activeIndex}` : undefined}
        disabled={disabled}
        onClick={() => setOpen((value) => !value)}
        onKeyDown={(event) => {
          if (event.key === "Escape") {
            setOpen(false);
          } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            if (!open) setOpen(true);
            else move(event.key === "ArrowDown" ? 1 : -1);
          } else if (event.key === "Enter" && open) {
            event.preventDefault();
            choose(activeIndex);
          }
        }}
      >
        <span>{selected?.label ?? String(value)}</span>
        <ChevronDown size={16} aria-hidden="true" />
      </button>
      <div
        className="glass-select-menu"
        id={listId}
        role="listbox"
        aria-label={ariaLabel}
        aria-hidden={!open}
      >
        {options.map((option, index) => (
          <button
            id={`${listId}-${index}`}
            type="button"
            role="option"
            aria-selected={option.value === value}
            disabled={option.disabled}
            className={activeIndex === index ? "active" : ""}
            key={String(option.value)}
            onPointerEnter={() => setActiveIndex(index)}
            onClick={() => choose(index)}
            tabIndex={-1}
          >
            <span>{option.label}</span>
            {option.value === value && <Check size={16} aria-hidden="true" />}
          </button>
        ))}
      </div>
    </div>
  );
}
