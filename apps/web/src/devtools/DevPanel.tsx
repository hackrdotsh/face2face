import { Card, CardPanel } from "@/components/ui/card";
import { Tabs, TabsList, TabsPanel, TabsTab } from "@/components/ui/tabs";
import { RawConsole } from "./RawConsole";
import { RequestLogView } from "./RequestLogView";
import { SessionInspector } from "./SessionInspector";
import { SimulatorPanel } from "./SimulatorPanel";

export function DevPanel() {
  return (
    <Card>
      <CardPanel>
        <Tabs defaultValue="requests">
          <TabsList>
            <TabsTab value="requests">Requests</TabsTab>
            <TabsTab value="session">Session</TabsTab>
            <TabsTab value="console">Console</TabsTab>
            <TabsTab value="simulator">Simulator</TabsTab>
          </TabsList>
          <TabsPanel value="requests">
            <RequestLogView />
          </TabsPanel>
          <TabsPanel value="session">
            <SessionInspector />
          </TabsPanel>
          <TabsPanel value="console">
            <RawConsole />
          </TabsPanel>
          <TabsPanel value="simulator">
            <SimulatorPanel />
          </TabsPanel>
        </Tabs>
      </CardPanel>
    </Card>
  );
}
