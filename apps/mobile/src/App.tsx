import { useState } from "react";
import { Button, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { checkAPI } from "./api";

type Connection = "idle" | "checking" | "connected" | "failed";

const connectionLabels: Record<Connection, string> = {
  idle: "API connection not checked",
  checking: "Checking API connection…",
  connected: "API connected",
  failed:
    "Cannot reach the API. Start the API server and check the configured address.",
};

export default function App() {
  const [connection, setConnection] = useState<Connection>("idle");

  async function connect() {
    setConnection("checking");
    try {
      await checkAPI();
      setConnection("connected");
    } catch {
      setConnection("failed");
    }
  }

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen}>
        <ScrollView contentContainerStyle={styles.content}>
          <Text accessibilityRole="header" style={styles.title}>
            face2face
          </Text>
          <Text style={styles.description}>
            Development build. Nearby discovery is not available yet.
          </Text>
          <View style={styles.connection}>
            <Text accessibilityLiveRegion="polite" style={styles.status}>
              {connectionLabels[connection]}
            </Text>
            <Button
              title="Check API connection"
              onPress={connect}
              disabled={connection === "checking"}
              color="#202020"
            />
          </View>
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#ffffff" },
  content: {
    padding: 24,
    gap: 24,
    maxWidth: 560,
    width: "100%",
    alignSelf: "center",
  },
  title: { fontSize: 36, fontWeight: "700", color: "#202020" },
  description: { fontSize: 18, lineHeight: 27, color: "#404040" },
  connection: { gap: 16 },
  status: { fontSize: 16, lineHeight: 24, color: "#202020" },
});
