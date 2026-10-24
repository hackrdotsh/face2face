import { DevPanel } from "@/devtools/DevPanel";
import { RootScreen } from "@/screens/RootScreen";
import { ServerBar } from "@/screens/ServerBar";
import { SessionProvider } from "@/session/session";

export function App() {
  return (
    <SessionProvider>
      <div className="min-h-dvh bg-background text-foreground">
        <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-3">
          <h1 className="font-semibold">face2face</h1>
          <ServerBar />
        </header>
        <main className="mx-auto grid max-w-6xl gap-6 p-4 lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]">
          <section>
            <RootScreen />
          </section>
          <aside>
            <DevPanel />
          </aside>
        </main>
      </div>
    </SessionProvider>
  );
}
