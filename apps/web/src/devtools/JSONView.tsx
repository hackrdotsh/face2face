export function JSONView({ value }: { value: unknown }) {
  if (value === undefined || value === null) {
    return <p className="text-muted-foreground text-xs">No body</p>;
  }
  return (
    <pre className="max-h-80 overflow-auto rounded-lg bg-muted p-2 font-mono text-xs">
      {typeof value === "string" ? value : JSON.stringify(value, null, 2)}
    </pre>
  );
}
