export interface SegmentedControlProps<Value extends string> {
  label: string;
  value: Value;
  options: ReadonlyArray<{ value: Value; title: string }>;
  disabled?: boolean;
  onChange: (value: Value) => void;
}

/** A choice among a few alternatives, shown side by side. */
export function SegmentedControl<Value extends string>({
  label,
  value,
  options,
  disabled = false,
  onChange,
}: SegmentedControlProps<Value>) {
  return (
    <div className="segmented" role="radiogroup" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={option.value === value}
          disabled={disabled}
          onClick={() => {
            if (option.value !== value) onChange(option.value);
          }}
        >
          {option.title}
        </button>
      ))}
    </div>
  );
}
