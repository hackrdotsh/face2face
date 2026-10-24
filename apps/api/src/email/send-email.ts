export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
}

export type SendEmail = (message: EmailMessage) => Promise<void>;

const resendEndpoint = "https://api.resend.com/emails";

export function createEmailSender(env: Env): SendEmail {
  if (env.EMAIL_TRANSPORT === "console") return logEmail;
  const apiKey = env.RESEND_API_KEY;
  if (!apiKey) throw new Error("RESEND_API_KEY is required to send email");
  return (message) => sendWithResend(apiKey, env.EMAIL_FROM, message);
}

async function logEmail(message: EmailMessage) {
  console.info(JSON.stringify({ event: "development_email", ...message }));
}

async function sendWithResend(
  apiKey: string,
  from: string,
  message: EmailMessage,
) {
  const response = await fetch(resendEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [message.to],
      subject: message.subject,
      text: message.text,
    }),
  });
  if (!response.ok) {
    throw new Error(`Resend rejected the email with HTTP ${response.status}`);
  }
}
