/** Signed paths to square variants. Show them as circles. */
export interface ProfilePhoto {
  large: string;
  thumb: string;
}

/** A photo, or a blob avatar drawn from `seed` when there is none. */
export interface Avatar {
  seed: string;
  photo: ProfilePhoto | null;
}

export interface User {
  id: string;
  name: string;
  email: string;
  avatar: Avatar;
}

export interface Account {
  user: User;
  onboardingComplete: boolean;
}

export interface ChoiceOption {
  id: string;
  label: string;
  allowsDescription: boolean;
}

export interface ChoiceValue {
  optionId: string;
  description?: string;
}

export type FieldValue = string | ChoiceValue;

export interface FieldConstraints {
  maxLength?: number;
  earliestDate?: string;
  latestDate?: string;
}

/** `type` stays open so a field type added on the server reaches the UI as unsupported instead of failing. */
export interface OnboardingField {
  key: string;
  type: "text" | "date" | "singleChoice" | "image" | (string & {});
  label: string;
  required: boolean;
  /** An `image` field holds the uploaded photo. It is set by uploading, not by an update. */
  value: FieldValue | ProfilePhoto | null;
  constraints?: FieldConstraints;
  options?: ChoiceOption[];
}

export interface OnboardingState {
  complete: boolean;
  fields: OnboardingField[];
}

export interface Passkey {
  id: string;
  name?: string | null;
  deviceType: string;
  backedUp: boolean;
  createdAt: string;
}

export interface CoordinatorStatus {
  ready: boolean;
  storage: string;
}

export type ConnectionStatus =
  | "pending"
  | "expired"
  | "private"
  | "public"
  | "blocked";
export type ConnectionDecision = "accepted" | "declined";

export interface Person {
  userId: string;
  name: string;
  avatar: Avatar;
}

export interface PublicProfile extends Person {
  age: number | null;
  interests: string[];
}

/** A connection as one participant sees it. `them` stays null until both people go public. */
export interface Connection {
  id: string;
  status: ConnectionStatus;
  sharedInterests: string[];
  you: {
    decision: ConnectionDecision | null;
    decidedAt: string | null;
    publicAt: string | null;
  };
  them: PublicProfile | null;
  createdAt: string;
  expiresAt: string;
  resolvedAt: string | null;
}

export type NotificationEvent =
  | {
      kind: "encounter";
      connectionId: string;
      sharedInterests: string[];
      expiresAt: string;
    }
  | { kind: "connected"; connectionId: string }
  | { kind: "public"; connectionId: string }
  | { kind: "message"; chatId: string }
  | {
      kind: "post_updated" | "post_cancelled" | "post_rsvp";
      postId: string;
      forumId: string;
    };

export type AppNotification = NotificationEvent & {
  id: string;
  createdAt: string;
};

export interface SocketTicket {
  ticket: string;
  expiresAt: string;
}

export type ImageVariantName = "original" | "preview" | "thumb";

export interface ImageVariant {
  /** Signed and relative to the server URL. It expires, so reload the message for a new one. */
  path: string;
  width: number;
  height: number;
}

export interface ChatImage {
  id: string;
  variants: Record<ImageVariantName, ImageVariant>;
}

/** A chat message as one participant sees it. It never names either person. */
export interface ChatMessage {
  id: string;
  clientId: string | null;
  from: "you" | "them";
  text: string | null;
  image: ChatImage | null;
  createdAt: string;
}

export interface ChatSummary {
  id: string;
  connection: Connection;
  lastMessage: ChatMessage | null;
  unreadCount: number;
}

export interface MessagePage {
  messages: ChatMessage[];
  hasMore: boolean;
}

export interface ChatActivity {
  chatId: string;
  messageId: string;
  createdAt: string;
}

export type TypingState = "started" | "stopped";

export type ChatClientFrame =
  | { type: "send"; clientId: string; text?: string; imageId?: string }
  | { type: "typing"; state: TypingState }
  | { type: "read"; messageId: string };

export type ChatServerFrame =
  | { type: "ready" }
  | { type: "pong" }
  | { type: "ack"; clientId: string; message: ChatMessage }
  | { type: "message"; message: ChatMessage }
  | { type: "typing"; state: TypingState }
  | { type: "error"; error: string; clientId?: string }
  | { type: "closed" };

export interface DevUser {
  id: string;
  name: string;
  email: string;
  seeded: boolean;
  interests: string[];
}

/** A raw connection row, with the low and high sides the API hides from participants. */
export interface DevConnection {
  id: string;
  userLowId: string;
  userHighId: string;
  status: ConnectionStatus;
  sharedInterests: string[];
  lowDecision: ConnectionDecision | null;
  highDecision: ConnectionDecision | null;
  lowPublicAt: string | null;
  highPublicAt: string | null;
  blockedBy: "low" | "high" | null;
  createdAt: string;
  expiresAt: string;
  resolvedAt: string | null;
}

export interface SimulatedEncounter {
  simulated: true;
  outcome: "created" | "alreadyActive" | "ignored";
  connection: DevConnection | null;
}

export interface InterestChoice {
  id: string;
  name: string;
  memberCount: number;
  selected: boolean;
}

export interface InterestChoices {
  maxSelected: number;
  interests: InterestChoice[];
}

export interface Forum {
  id: string;
  interestId: string;
  interestName: string;
  upcomingPostCount: number;
}

export interface Post {
  id: string;
  forumId: string;
  title: string;
  description: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string | null;
  createdAt: string;
  updatedAt: string;
  author: Person;
  attendeeCount: number;
  /** The first few attendees, by RSVP time. */
  attendeePreview: Person[];
  attending: boolean;
  isAuthor: boolean;
  edited: boolean;
  past: boolean;
  cancelled: boolean;
}

export interface PostPage {
  posts: Post[];
  hasMore: boolean;
}

/** `null` clears a field. */
export interface PostInput {
  title: string;
  description: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string | null;
}
