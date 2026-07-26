"use client";

import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import {
  RefreshCoordinator,
  shouldExpireSessionAfterRefresh,
} from "./session-refresh";
import {
  WorkspaceLoadGuard,
  type WorkspaceLoadTicket,
} from "./workspace-load";

const PROFILES_KEY = "inspirat.test-console.profiles.v1";
const ACTIVE_PROFILE_KEY = "inspirat.test-console.active-profile.v1";
const API_URL_KEY = "inspirat.test-console.api-url.v1";
const DEFAULT_API_URL = "http://localhost:8000/api/v1";
const DEMO_PASSWORD = "InspiraT-demo-2026!";
const DEMO_PROFILES = [
  {
    name: "Inés Valdivia — demo",
    identity: "ines@example.com",
  },
  {
    name: "Mateo Rojas — demo",
    identity: "mateo@example.com",
  },
] as const;

type Person = {
  id: string;
  name: string;
  identity: string;
  password: string;
  accessToken?: string;
  refreshToken?: string;
  user?: CommunityUser;
  connectedAt?: string;
};

type TokenPair = {
  access_token: string;
  refresh_token: string;
  user: CommunityUser;
};

type CommunityUser = {
  id: string;
  display_name?: string;
  username?: string;
  email?: string;
};

type Project = {
  id: string;
  title: string;
  subtitle?: string | null;
  updated_at?: string;
};

type StoryDocument = {
  id: string;
  project_id: string;
  title: string;
  content?: string;
  word_count?: number;
  revision?: number;
};

type ChatDocument = {
  id?: string;
  title?: string;
  content?: string;
  owner_name?: string;
};

type ChatMessage = {
  id: string;
  body?: string;
  content?: string;
  text?: string;
  sender_id?: string;
  author_id?: string;
  created_at?: string;
  sent_at?: string;
  sender?: CommunityUser;
  author?: CommunityUser;
  document?: ChatDocument | null;
  document_title?: string | null;
};

type Conversation = {
  id?: string;
  user_id?: string;
  peer_id?: string;
  user?: CommunityUser;
  peer?: CommunityUser;
  other_user?: CommunityUser;
  last_message?: ChatMessage | string | null;
  unread_count?: number;
};

type Status = {
  kind: "idle" | "working" | "success" | "error";
  text: string;
};

type Panel = "people" | "workshop" | "messages";

class ApiRequestError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiRequestError";
  }
}

function makeId() {
  return globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
}

function cleanApiUrl(value: string) {
  return value.trim().replace(/\/+$/, "");
}

function listFrom<T>(value: unknown, keys: string[]): T[] {
  if (Array.isArray(value)) return value as T[];
  if (!value || typeof value !== "object") return [];
  const record = value as Record<string, unknown>;
  for (const key of keys) {
    if (Array.isArray(record[key])) return record[key] as T[];
  }
  return [];
}

function apiError(payload: unknown, status: number) {
  if (payload && typeof payload === "object") {
    const detail = (payload as Record<string, unknown>).detail;
    if (typeof detail === "string") return detail;
    if (Array.isArray(detail)) {
      const messages = detail
        .map((item) =>
          item && typeof item === "object"
            ? String((item as Record<string, unknown>).msg ?? "")
            : "",
        )
        .filter(Boolean);
      if (messages.length) return messages.join(" · ");
    }
  }
  return `La API respondió con el código ${status}.`;
}

function userName(user?: CommunityUser | null) {
  return (
    user?.display_name?.trim() ||
    user?.username?.trim() ||
    user?.email?.trim() ||
    "Persona sin nombre"
  );
}

function initials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "IT"
  );
}

function messageText(message: ChatMessage) {
  return message.body ?? message.content ?? message.text ?? "";
}

function messageDate(message: ChatMessage) {
  const value = message.created_at ?? message.sent_at;
  if (!value) return "";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) return "";
  return new Intl.DateTimeFormat("es-CL", {
    hour: "2-digit",
    minute: "2-digit",
    day: "2-digit",
    month: "short",
  }).format(parsed);
}

function conversationUser(conversation: Conversation) {
  return conversation.other_user ?? conversation.peer ?? conversation.user;
}

function conversationUserId(conversation: Conversation) {
  return (
    conversationUser(conversation)?.id ??
    conversation.peer_id ??
    conversation.user_id ??
    ""
  );
}

function lastMessageText(conversation: Conversation) {
  if (!conversation.last_message) return "Sin mensajes todavía";
  if (typeof conversation.last_message === "string") {
    return conversation.last_message;
  }
  return messageText(conversation.last_message) || "Documento compartido";
}

export function TesterConsole() {
  const [ready, setReady] = useState(false);
  const [apiUrl, setApiUrl] = useState(DEFAULT_API_URL);
  const apiUrlRef = useRef(DEFAULT_API_URL);
  const [profiles, setProfiles] = useState<Person[]>([]);
  const [activeProfileId, setActiveProfileId] = useState("");
  const profilesRef = useRef<Person[]>([]);
  const activeProfileIdRef = useRef("");
  const refreshCoordinatorRef = useRef(new RefreshCoordinator<Person>());
  const workspaceLoadGuardRef = useRef(new WorkspaceLoadGuard());
  const [panel, setPanel] = useState<Panel>("people");
  const [workspaceLoading, setWorkspaceLoading] = useState(false);
  const [status, setStatus] = useState<Status>({
    kind: "idle",
    text: "Agrega una persona de prueba para comenzar.",
  });

  const [editingId, setEditingId] = useState("");
  const [personName, setPersonName] = useState("");
  const [personIdentity, setPersonIdentity] = useState("");
  const [personPassword, setPersonPassword] = useState("");

  const [communityUsers, setCommunityUsers] = useState<CommunityUser[]>([]);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [documents, setDocuments] = useState<StoryDocument[]>([]);
  const [projectTitle, setProjectTitle] = useState("");
  const [chapterTitle, setChapterTitle] = useState("Capítulo 1");
  const [chapterContent, setChapterContent] = useState("");
  const [selectedProjectId, setSelectedProjectId] = useState("");

  const [chatTarget, setChatTarget] = useState("general");
  const chatTargetRef = useRef("general");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [messageDraft, setMessageDraft] = useState("");
  const [attachedDocumentId, setAttachedDocumentId] = useState("");

  const activePerson = useMemo(
    () => profiles.find((person) => person.id === activeProfileId),
    [profiles, activeProfileId],
  );
  const activeUserId = activePerson?.user?.id;
  const availableUsers = communityUsers.filter(
    (person) => person.id !== activeUserId,
  );
  const selectedChatUser = availableUsers.find(
    (person) => person.id === chatTarget,
  );

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const storedProfiles = JSON.parse(
          localStorage.getItem(PROFILES_KEY) ?? "[]",
        ) as Person[];
        const storedActive = localStorage.getItem(ACTIVE_PROFILE_KEY) ?? "";
        const storedApiUrl = localStorage.getItem(API_URL_KEY);
        const validProfiles = Array.isArray(storedProfiles)
          ? storedProfiles
          : [];
        profilesRef.current = validProfiles;
        setProfiles(validProfiles);
        const initialProfileId = validProfiles.some(
          (person) => person.id === storedActive,
        )
          ? storedActive
          : (validProfiles[0]?.id ?? "");
        if (storedApiUrl) {
          apiUrlRef.current = storedApiUrl;
          setApiUrl(storedApiUrl);
        }
        activatePerson(initialProfileId);
      } catch {
        setStatus({
          kind: "error",
          text: "No se pudieron leer los perfiles guardados en este navegador.",
        });
      } finally {
        setReady(true);
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem(PROFILES_KEY, JSON.stringify(profiles));
  }, [profiles, ready]);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem(ACTIVE_PROFILE_KEY, activeProfileId);
  }, [activeProfileId, ready]);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem(API_URL_KEY, cleanApiUrl(apiUrl));
  }, [apiUrl, ready]);

  function clearWorkspaceData() {
    setCommunityUsers([]);
    setConversations([]);
    setProjects([]);
    setDocuments([]);
    setMessages([]);
    setSelectedProjectId("");
    chatTargetRef.current = "general";
    setChatTarget("general");
    setMessagesLoading(false);
  }

  function activatePerson(personId: string) {
    const ticket = workspaceLoadGuardRef.current.begin(personId);
    activeProfileIdRef.current = personId;
    setActiveProfileId(personId);
    clearWorkspaceData();
    const person = profilesRef.current.find(
      (profile) => profile.id === personId,
    );
    if (!person?.accessToken) {
      setWorkspaceLoading(false);
      return;
    }
    setWorkspaceLoading(true);
    setStatus({
      kind: "working",
      text: `Cargando la comunidad de ${person.name}…`,
    });
    void loadWorkspaceForPerson(person, ticket, true);
  }

  function changeApiUrl(value: string) {
    apiUrlRef.current = value;
    setApiUrl(value);
  }

  function replaceProfiles(nextProfiles: Person[]) {
    profilesRef.current = nextProfiles;
    setProfiles(nextProfiles);
    if (!ready) return;
    try {
      localStorage.setItem(PROFILES_KEY, JSON.stringify(nextProfiles));
    } catch {
      // The state remains usable for the current tab even if storage is blocked.
    }
  }

  function updatePerson(id: string, patch: Partial<Person>) {
    replaceProfiles(
      profilesRef.current.map((person) =>
        person.id === id ? { ...person, ...patch } : person,
      ),
    );
  }

  async function fetchApi<T>(
    path: string,
    init: RequestInit = {},
    token?: string | null,
  ): Promise<T> {
    const headers = new Headers(init.headers);
    if (init.body) headers.set("Content-Type", "application/json");
    if (token) headers.set("Authorization", `Bearer ${token}`);
    let response: Response;
    try {
      response = await fetch(`${cleanApiUrl(apiUrlRef.current)}${path}`, {
        ...init,
        headers,
      });
    } catch {
      throw new Error(
        "No se pudo alcanzar la API. Comprueba Docker, la dirección y CORS.",
      );
    }
    const text = await response.text();
    let payload: unknown = null;
    if (text) {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = text;
      }
    }
    if (!response.ok) {
      throw new ApiRequestError(
        response.status,
        apiError(payload, response.status),
      );
    }
    return payload as T;
  }

  function expirePersonSession(profileId: string) {
    const person = profilesRef.current.find(
      (profile) => profile.id === profileId,
    );
    if (person) {
      updatePerson(profileId, {
        accessToken: undefined,
        refreshToken: undefined,
        user: undefined,
        connectedAt: undefined,
      });
    }
    const message = `La sesión de ${
      person?.name ?? "esta persona"
    } expiró. Iníciala nuevamente.`;
    if (profileId === activeProfileIdRef.current) {
      workspaceLoadGuardRef.current.invalidate();
      clearWorkspaceData();
      setWorkspaceLoading(false);
      setStatus({ kind: "error", text: message });
    }
    return message;
  }

  function refreshPersonSession(profileId: string) {
    return refreshCoordinatorRef.current.run(profileId, async () => {
      const current = profilesRef.current.find(
        (person) => person.id === profileId,
      );
      const refreshToken = current?.refreshToken;
      if (!current || !refreshToken) {
        throw new Error(expirePersonSession(profileId));
      }

      let result: TokenPair;
      try {
        result = await fetchApi<TokenPair>(
          "/auth/refresh",
          {
            method: "POST",
            body: JSON.stringify({
              refresh_token: refreshToken,
              device_name: "Consola local de pruebas",
            }),
          },
          null,
        );
      } catch (error) {
        if (
          error instanceof ApiRequestError &&
          shouldExpireSessionAfterRefresh(error.status)
        ) {
          throw new Error(expirePersonSession(profileId));
        }
        throw error;
      }

      const latest = profilesRef.current.find(
        (person) => person.id === profileId,
      );
      if (!latest || latest.refreshToken !== refreshToken) {
        throw new Error(
          "La sesión cambió mientras se renovaba. Repite la acción.",
        );
      }
      const refreshedPerson: Person = {
        ...latest,
        accessToken: result.access_token,
        refreshToken: result.refresh_token,
        user: result.user,
        connectedAt: new Date().toISOString(),
      };
      updatePerson(profileId, refreshedPerson);
      return refreshedPerson;
    });
  }

  async function request<T>(
    path: string,
    init: RequestInit = {},
    person: Person | null | undefined = activePerson,
  ): Promise<T> {
    const currentPerson = person
      ? (profilesRef.current.find((profile) => profile.id === person.id) ??
        person)
      : null;
    try {
      return await fetchApi<T>(path, init, currentPerson?.accessToken);
    } catch (error) {
      if (
        !(error instanceof ApiRequestError) ||
        error.status !== 401 ||
        !currentPerson
      ) {
        throw error;
      }
    }

    const latestPerson = profilesRef.current.find(
      (profile) => profile.id === currentPerson.id,
    );
    if (
      latestPerson?.accessToken &&
      latestPerson.accessToken !== currentPerson.accessToken
    ) {
      try {
        return await fetchApi<T>(path, init, latestPerson.accessToken);
      } catch (error) {
        if (error instanceof ApiRequestError && error.status === 401) {
          throw new Error(expirePersonSession(currentPerson.id));
        }
        throw error;
      }
    }

    const refreshedPerson = await refreshPersonSession(currentPerson.id);
    try {
      return await fetchApi<T>(path, init, refreshedPerson.accessToken);
    } catch (error) {
      if (error instanceof ApiRequestError && error.status === 401) {
        throw new Error(expirePersonSession(currentPerson.id));
      }
      throw error;
    }
  }

  function resetPersonForm() {
    setEditingId("");
    setPersonName("");
    setPersonIdentity("");
    setPersonPassword("");
  }

  function loadDemoProfiles() {
    const existingIdentities = new Set(
      profiles.map((person) => person.identity.trim().toLowerCase()),
    );
    const additions: Person[] = DEMO_PROFILES.filter(
      (person) => !existingIdentities.has(person.identity),
    ).map((person) => ({
      id: makeId(),
      ...person,
      password: DEMO_PASSWORD,
    }));
    if (additions.length === 0) {
      setStatus({
        kind: "idle",
        text: "Inés y Mateo ya están guardados en esta consola.",
      });
      return;
    }
    const nextProfiles = [...profiles, ...additions];
    replaceProfiles(nextProfiles);
    if (!activeProfileId) activatePerson(nextProfiles[0]?.id ?? "");
    setStatus({
      kind: "success",
      text: "Perfiles demo cargados. Inicia cada sesión para comenzar.",
    });
  }

  function savePerson(event: FormEvent) {
    event.preventDefault();
    const name = personName.trim();
    const identity = personIdentity.trim();
    if (!name || !identity || !personPassword) {
      setStatus({
        kind: "error",
        text: "Completa el nombre, la identidad y la contraseña.",
      });
      return;
    }
    if (editingId) {
      refreshCoordinatorRef.current.clear(editingId);
      updatePerson(editingId, {
        name,
        identity,
        password: personPassword,
        accessToken: undefined,
        refreshToken: undefined,
        user: undefined,
      });
      if (editingId === activeProfileIdRef.current) {
        workspaceLoadGuardRef.current.invalidate();
        clearWorkspaceData();
        setWorkspaceLoading(false);
      }
      setStatus({
        kind: "success",
        text: `${name} fue actualizado. Inicia su sesión nuevamente.`,
      });
    } else {
      const newPerson: Person = {
        id: makeId(),
        name,
        identity,
        password: personPassword,
      };
      replaceProfiles([...profilesRef.current, newPerson]);
      activatePerson(newPerson.id);
      setStatus({
        kind: "success",
        text: `${name} quedó guardado en esta consola.`,
      });
    }
    resetPersonForm();
  }

  function editPerson(person: Person) {
    setEditingId(person.id);
    setPersonName(person.name);
    setPersonIdentity(person.identity);
    setPersonPassword(person.password);
  }

  function removePerson(person: Person) {
    if (!window.confirm(`¿Quitar a ${person.name} de esta consola local?`)) {
      return;
    }
    refreshCoordinatorRef.current.clear(person.id);
    replaceProfiles(
      profilesRef.current.filter((item) => item.id !== person.id),
    );
    if (activeProfileId === person.id) {
      const replacement = profiles.find((item) => item.id !== person.id);
      activatePerson(replacement?.id ?? "");
    }
    if (editingId === person.id) resetPersonForm();
  }

  async function loginPerson(person: Person) {
    setStatus({ kind: "working", text: `Conectando como ${person.name}…` });
    try {
      const result = await request<TokenPair>(
        "/auth/login",
        {
          method: "POST",
          body: JSON.stringify({
            identity: person.identity,
            password: person.password,
            device_name: "Consola local de pruebas",
          }),
        },
        null,
      );
      refreshCoordinatorRef.current.clear(person.id);
      updatePerson(person.id, {
        accessToken: result.access_token,
        refreshToken: result.refresh_token,
        user: result.user,
        connectedAt: new Date().toISOString(),
      });
      activatePerson(person.id);
      setStatus({
        kind: "success",
        text: `Sesión iniciada como ${userName(result.user)}.`,
      });
    } catch (error) {
      setStatus({
        kind: "error",
        text: error instanceof Error ? error.message : "No se pudo iniciar sesión.",
      });
    }
  }

  function forgetSession(person: Person) {
    refreshCoordinatorRef.current.clear(person.id);
    updatePerson(person.id, {
      accessToken: undefined,
      refreshToken: undefined,
      user: undefined,
      connectedAt: undefined,
    });
    if (person.id === activeProfileIdRef.current) {
      workspaceLoadGuardRef.current.invalidate();
      clearWorkspaceData();
      setWorkspaceLoading(false);
    }
    setStatus({
      kind: "success",
      text: `La sesión de ${person.name} se quitó de esta consola.`,
    });
  }

  function isCurrentWorkspace(ticket: WorkspaceLoadTicket) {
    return workspaceLoadGuardRef.current.isCurrent(ticket);
  }

  async function loadUsers(
    showStatus = true,
    person?: Person,
    ticket = workspaceLoadGuardRef.current.current(),
  ) {
    const requestPerson =
      person ??
      profilesRef.current.find((profile) => profile.id === ticket.profileId);
    if (!requestPerson?.accessToken) return false;
    if (showStatus) {
      setStatus({ kind: "working", text: "Consultando usuarios…" });
    }
    try {
      const payload = await request<unknown>(
        "/community/users",
        {},
        requestPerson,
      );
      if (!isCurrentWorkspace(ticket)) return true;
      setCommunityUsers(
        listFrom<CommunityUser>(payload, ["users", "items", "results"]),
      );
      if (showStatus) {
        setStatus({ kind: "success", text: "Lista de usuarios actualizada." });
      }
      return true;
    } catch (error) {
      if (showStatus && isCurrentWorkspace(ticket)) {
        setStatus({
          kind: "error",
          text: error instanceof Error ? error.message : "No se pudieron cargar los usuarios.",
        });
      }
      return false;
    }
  }

  async function loadConversations(
    showStatus = false,
    person?: Person,
    ticket = workspaceLoadGuardRef.current.current(),
  ) {
    const requestPerson =
      person ??
      profilesRef.current.find((profile) => profile.id === ticket.profileId);
    if (!requestPerson?.accessToken) return false;
    try {
      const payload = await request<unknown>(
        "/community/conversations",
        {},
        requestPerson,
      );
      if (!isCurrentWorkspace(ticket)) return true;
      setConversations(
        listFrom<Conversation>(payload, [
          "conversations",
          "items",
          "results",
        ]),
      );
      return true;
    } catch (error) {
      if (showStatus && isCurrentWorkspace(ticket)) {
        setStatus({
          kind: "error",
          text:
            error instanceof Error
              ? error.message
              : "No se pudieron cargar las conversaciones.",
        });
      }
      return false;
    }
  }

  async function loadProjects(
    showStatus = true,
    person?: Person,
    ticket = workspaceLoadGuardRef.current.current(),
  ) {
    const requestPerson =
      person ??
      profilesRef.current.find((profile) => profile.id === ticket.profileId);
    if (!requestPerson?.accessToken) return false;
    if (showStatus) {
      setStatus({ kind: "working", text: "Cargando el taller…" });
    }
    try {
      const projectPayload = await request<unknown>(
        "/projects",
        {},
        requestPerson,
      );
      const nextProjects = listFrom<Project>(projectPayload, [
        "projects",
        "items",
        "results",
      ]);
      const documentGroups = await Promise.all(
        nextProjects.map(async (project) => {
          const payload = await request<unknown>(
            `/projects/${encodeURIComponent(project.id)}/documents`,
            {},
            requestPerson,
          );
          return listFrom<StoryDocument>(payload, [
            "documents",
            "items",
            "results",
          ]);
        }),
      );
      if (!isCurrentWorkspace(ticket)) return true;
      setProjects(nextProjects);
      setDocuments(documentGroups.flat());
      setSelectedProjectId((current) =>
        nextProjects.some((project) => project.id === current)
          ? current
          : (nextProjects[0]?.id ?? ""),
      );
      if (showStatus) {
        setStatus({ kind: "success", text: "Contenido actualizado." });
      }
      return true;
    } catch (error) {
      if (showStatus && isCurrentWorkspace(ticket)) {
        setStatus({
          kind: "error",
          text: error instanceof Error ? error.message : "No se pudo cargar el taller.",
        });
      }
      return false;
    }
  }

  async function loadMessages(
    target = chatTargetRef.current,
    showStatus = false,
    person?: Person,
    ticket = workspaceLoadGuardRef.current.current(),
  ) {
    const requestPerson =
      person ??
      profilesRef.current.find((profile) => profile.id === ticket.profileId);
    if (!requestPerson?.accessToken) return false;
    try {
      const path =
        target === "general"
          ? "/community/general/messages"
          : `/community/direct/${encodeURIComponent(target)}/messages`;
      const payload = await request<unknown>(path, {}, requestPerson);
      const loadedMessages = listFrom<ChatMessage>(payload, [
        "messages",
        "items",
        "results",
      ]);
      if (
        !isCurrentWorkspace(ticket) ||
        chatTargetRef.current !== target
      ) {
        return true;
      }
      setMessages([...loadedMessages].reverse());
      if (target !== "general") {
        await request<unknown>(
          `/community/direct/${encodeURIComponent(target)}/read`,
          { method: "POST" },
          requestPerson,
        );
        if (
          !isCurrentWorkspace(ticket) ||
          chatTargetRef.current !== target
        ) {
          return true;
        }
        setConversations((current) =>
          current.map((conversation) =>
            conversationUserId(conversation) === target
              ? { ...conversation, unread_count: 0 }
              : conversation,
          ),
        );
      }
      if (showStatus) {
        setStatus({ kind: "success", text: "Mensajes actualizados." });
      }
      return true;
    } catch (error) {
      if (
        showStatus &&
        isCurrentWorkspace(ticket) &&
        chatTargetRef.current === target
      ) {
        setStatus({
          kind: "error",
          text: error instanceof Error ? error.message : "No se pudieron cargar los mensajes.",
        });
      }
      return false;
    }
  }

  async function loadWorkspaceForPerson(
    person: Person,
    ticket: WorkspaceLoadTicket,
    showStatus: boolean,
    target = "general",
  ) {
    const results = await Promise.all([
      loadUsers(false, person, ticket),
      loadConversations(false, person, ticket),
      loadProjects(false, person, ticket),
      loadMessages(target, false, person, ticket),
    ]);
    if (!isCurrentWorkspace(ticket)) return;

    setWorkspaceLoading(false);
    setMessagesLoading(false);
    if (!showStatus) return;
    const failures = results.filter((result) => result === false);
    setStatus(
      failures.length
        ? {
            kind: "error",
            text: "Parte de la información no pudo actualizarse.",
          }
        : {
            kind: "success",
            text: `Comunidad cargada para ${person.name}.`,
          },
    );
  }

  async function refreshWorkspace(showStatus = true) {
    const person = profilesRef.current.find(
      (profile) => profile.id === activeProfileIdRef.current,
    );
    if (!person?.accessToken) {
      setStatus({
        kind: "error",
        text: "Inicia la sesión de la persona activa para consultar la API.",
      });
      return;
    }
    const ticket = workspaceLoadGuardRef.current.begin(person.id);
    setWorkspaceLoading(true);
    if (showStatus) {
      setStatus({ kind: "working", text: "Actualizando la consola…" });
    }
    await loadWorkspaceForPerson(
      person,
      ticket,
      showStatus,
      chatTargetRef.current,
    );
  }

  async function createProjectAndChapter(event: FormEvent) {
    event.preventDefault();
    if (!projectTitle.trim()) {
      setStatus({ kind: "error", text: "Escribe un título para el proyecto." });
      return;
    }
    const ticket = workspaceLoadGuardRef.current.current();
    const person = profilesRef.current.find(
      (profile) => profile.id === ticket.profileId,
    );
    if (!person?.accessToken) {
      setStatus({ kind: "error", text: "Primero inicia una sesión." });
      return;
    }
    setStatus({ kind: "working", text: "Creando proyecto y capítulo…" });
    try {
      const project = await request<Project>("/projects", {
        method: "POST",
        body: JSON.stringify({
          client_id: makeId(),
          title: projectTitle.trim(),
          synopsis: "",
          status: "draft",
          color: "#0B6B61",
        }),
      }, person);
      await request<StoryDocument>(
        `/projects/${encodeURIComponent(project.id)}/documents`,
        {
          method: "POST",
          body: JSON.stringify({
            client_id: makeId(),
            title: chapterTitle.trim() || "Capítulo 1",
            kind: "chapter",
            position: 0,
            content: chapterContent,
          }),
        },
        person,
      );
      if (!isCurrentWorkspace(ticket)) return;
      setProjectTitle("");
      setChapterTitle("Capítulo 1");
      setChapterContent("");
      await loadProjects(false, person, ticket);
      if (!isCurrentWorkspace(ticket)) return;
      setSelectedProjectId(project.id);
      setStatus({
        kind: "success",
        text: `“${project.title}” y su primer capítulo fueron creados.`,
      });
    } catch (error) {
      if (isCurrentWorkspace(ticket)) {
        setStatus({
          kind: "error",
          text:
            error instanceof Error
              ? error.message
              : "No se pudo crear el contenido.",
        });
      }
    }
  }

  async function createChapter() {
    const targetProjectId = selectedProjectId;
    if (!targetProjectId) {
      setStatus({ kind: "error", text: "Selecciona un proyecto." });
      return;
    }
    if (!chapterTitle.trim()) {
      setStatus({ kind: "error", text: "Escribe un título para el capítulo." });
      return;
    }
    const ticket = workspaceLoadGuardRef.current.current();
    const person = profilesRef.current.find(
      (profile) => profile.id === ticket.profileId,
    );
    if (!person?.accessToken) {
      setStatus({ kind: "error", text: "Primero inicia una sesión." });
      return;
    }
    setStatus({ kind: "working", text: "Creando capítulo…" });
    try {
      const projectDocuments = documents.filter(
        (document) => document.project_id === targetProjectId,
      );
      await request<StoryDocument>(
        `/projects/${encodeURIComponent(targetProjectId)}/documents`,
        {
          method: "POST",
          body: JSON.stringify({
            client_id: makeId(),
            title: chapterTitle.trim(),
            kind: "chapter",
            position: projectDocuments.length,
            content: chapterContent,
          }),
        },
        person,
      );
      if (!isCurrentWorkspace(ticket)) return;
      setChapterTitle(`Capítulo ${projectDocuments.length + 2}`);
      setChapterContent("");
      await loadProjects(false, person, ticket);
      if (isCurrentWorkspace(ticket)) {
        setStatus({ kind: "success", text: "Capítulo creado correctamente." });
      }
    } catch (error) {
      if (isCurrentWorkspace(ticket)) {
        setStatus({
          kind: "error",
          text:
            error instanceof Error ? error.message : "No se pudo crear el capítulo.",
        });
      }
    }
  }

  async function selectChat(target: string) {
    chatTargetRef.current = target;
    setChatTarget(target);
    setMessages([]);
    setMessagesLoading(true);
    setPanel("messages");
    const person = profilesRef.current.find(
      (profile) => profile.id === activeProfileIdRef.current,
    );
    const ticket = workspaceLoadGuardRef.current.current();
    try {
      await loadMessages(target, true, person, ticket);
    } finally {
      if (
        isCurrentWorkspace(ticket) &&
        chatTargetRef.current === target
      ) {
        setMessagesLoading(false);
      }
    }
  }

  async function sendMessage(event: FormEvent) {
    event.preventDefault();
    const body = messageDraft.trim();
    if (!body && !attachedDocumentId) {
      setStatus({
        kind: "error",
        text: "Escribe un mensaje o adjunta uno de tus cuentos.",
      });
      return;
    }
    const ticket = workspaceLoadGuardRef.current.current();
    const person = profilesRef.current.find(
      (profile) => profile.id === ticket.profileId,
    );
    const target = chatTargetRef.current;
    if (!person?.accessToken) {
      setStatus({ kind: "error", text: "Primero inicia una sesión." });
      return;
    }
    setStatus({ kind: "working", text: "Enviando mensaje…" });
    try {
      const path =
        target === "general"
          ? "/community/general/messages"
          : `/community/direct/${encodeURIComponent(target)}/messages`;
      const outgoingMessage = {
        body,
        client_id: makeId(),
        ...(attachedDocumentId
          ? { document_id: attachedDocumentId }
          : {}),
      };
      await request<ChatMessage>(path, {
        method: "POST",
        body: JSON.stringify(outgoingMessage),
      }, person);
      if (
        !isCurrentWorkspace(ticket) ||
        chatTargetRef.current !== target
      ) {
        return;
      }
      setMessageDraft("");
      setAttachedDocumentId("");
      await Promise.all([
        loadMessages(target, false, person, ticket),
        loadConversations(false, person, ticket),
      ]);
      if (
        isCurrentWorkspace(ticket) &&
        chatTargetRef.current === target
      ) {
        setStatus({ kind: "success", text: "Mensaje enviado." });
      }
    } catch (error) {
      if (
        isCurrentWorkspace(ticket) &&
        chatTargetRef.current === target
      ) {
        setStatus({
          kind: "error",
          text: error instanceof Error ? error.message : "No se pudo enviar el mensaje.",
        });
      }
    }
  }

  if (!ready) {
    return (
      <main className="loading-shell">
        <div className="brand-mark" aria-hidden="true">
          iT
        </div>
        <p>Preparando la consola local…</p>
      </main>
    );
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand-block">
          <div className="brand-mark" aria-hidden="true">
            iT
          </div>
          <div>
            <p className="eyebrow">Consola local de pruebas</p>
            <h1>Comunidad inspíraT</h1>
          </div>
        </div>

        <div className="connection-tools">
          <label className="api-field">
            <span>Dirección de la API</span>
            <input
              aria-label="Dirección de la API"
              value={apiUrl}
              onChange={(event) => changeApiUrl(event.target.value)}
              spellCheck={false}
            />
          </label>
          <button
            className="secondary-button"
            type="button"
            onClick={() => refreshWorkspace()}
            disabled={!activePerson?.accessToken || status.kind === "working"}
          >
            Actualizar
          </button>
        </div>
      </header>

      <div className="active-strip">
        <div>
          <span className="status-dot" data-online={!!activePerson?.accessToken} />
          <strong>
            {activePerson
              ? `${activePerson.name}${
                  activePerson.accessToken ? " · sesión activa" : " · sin sesión"
                }`
              : "Sin persona activa"}
          </strong>
        </div>
        {profiles.length > 0 && (
          <label>
            <span className="sr-only">Persona activa</span>
            <select
              value={activeProfileId}
              onChange={(event) => activatePerson(event.target.value)}
            >
              {profiles.map((person) => (
                <option key={person.id} value={person.id}>
                  {person.name}
                </option>
              ))}
            </select>
          </label>
        )}
        <p className={`global-status ${status.kind}`} role="status">
          {status.text}
        </p>
      </div>

      <nav className="primary-nav" aria-label="Secciones de la consola">
        <button
          type="button"
          className={panel === "people" ? "active" : ""}
          onClick={() => setPanel("people")}
        >
          Personas de prueba
        </button>
        <button
          type="button"
          className={panel === "workshop" ? "active" : ""}
          onClick={() => {
            setPanel("workshop");
            void loadProjects(false);
          }}
        >
          Taller rápido
        </button>
        <button
          type="button"
          className={panel === "messages" ? "active" : ""}
          onClick={() => {
            setPanel("messages");
            void Promise.all([
              loadUsers(false),
              loadConversations(false),
              loadMessages(chatTarget, false),
            ]);
          }}
        >
          Compartidos y mensajes
        </button>
      </nav>

      {panel === "people" && (
        <section className="people-layout">
          <article className="surface intro-card">
            <p className="eyebrow">Banco de identidades</p>
            <h2>Prueba varios puntos de vista, desde un solo lugar.</h2>
            <p>
              Guarda usuarios existentes de la API, abre la sesión de cada uno y
              alterna entre ellos sin salir de esta página.
            </p>
            <div className="privacy-note">
              <strong>Solo para desarrollo local.</strong>
              <span>
                Las contraseñas y sesiones se guardan en el almacenamiento de
                este navegador. No publiques esta consola.
              </span>
            </div>
            <button
              className="quiet-button"
              type="button"
              onClick={loadDemoProfiles}
            >
              Cargar perfiles demo de Inés y Mateo
            </button>
          </article>

          <article className="surface form-card">
            <div className="section-heading">
              <div>
                <p className="eyebrow">
                  {editingId ? "Editar persona" : "Nueva persona"}
                </p>
                <h2>
                  {editingId ? "Actualiza sus credenciales" : "Añade un usuario"}
                </h2>
              </div>
            </div>
            <form className="stack-form" onSubmit={savePerson}>
              <label>
                Nombre para identificarlo aquí
                <input
                  value={personName}
                  onChange={(event) => setPersonName(event.target.value)}
                  placeholder="Ej. Martina — autora"
                />
              </label>
              <label>
                Correo o nombre de usuario
                <input
                  value={personIdentity}
                  onChange={(event) => setPersonIdentity(event.target.value)}
                  placeholder="martina@example.com"
                  autoCapitalize="none"
                  autoCorrect="off"
                />
              </label>
              <label>
                Contraseña
                <input
                  type="password"
                  value={personPassword}
                  onChange={(event) => setPersonPassword(event.target.value)}
                  placeholder="Contraseña de prueba"
                  autoComplete="new-password"
                />
              </label>
              <div className="button-row">
                <button className="primary-button" type="submit">
                  {editingId ? "Guardar cambios" : "Guardar persona"}
                </button>
                {editingId && (
                  <button
                    className="quiet-button"
                    type="button"
                    onClick={resetPersonForm}
                  >
                    Cancelar
                  </button>
                )}
              </div>
            </form>
          </article>

          <div className="profile-list">
            {profiles.length === 0 ? (
              <div className="surface empty-card">
                <span className="empty-symbol" aria-hidden="true">
                  +
                </span>
                <h3>Todavía no hay personas de prueba</h3>
                <p>Completa el formulario para guardar la primera.</p>
              </div>
            ) : (
              profiles.map((person) => (
                <article
                  className={`surface profile-card ${
                    person.id === activeProfileId ? "selected" : ""
                  }`}
                  key={person.id}
                >
                  <button
                    className="profile-main"
                    type="button"
                    onClick={() => activatePerson(person.id)}
                  >
                    <span className="avatar">{initials(person.name)}</span>
                    <span>
                      <strong>{person.name}</strong>
                      <small>{person.identity}</small>
                    </span>
                    <span
                      className="session-pill"
                      data-online={!!person.accessToken}
                    >
                      {person.accessToken ? "Conectado" : "Pendiente"}
                    </span>
                  </button>
                  <div className="profile-actions">
                    <button type="button" onClick={() => editPerson(person)}>
                      Editar
                    </button>
                    {person.accessToken ? (
                      <button
                        type="button"
                        onClick={() => forgetSession(person)}
                      >
                        Cerrar sesión local
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="accent-link"
                        onClick={() => loginPerson(person)}
                      >
                        Iniciar sesión
                      </button>
                    )}
                    <button
                      type="button"
                      className="danger-link"
                      onClick={() => removePerson(person)}
                    >
                      Quitar
                    </button>
                  </div>
                </article>
              ))
            )}
          </div>
        </section>
      )}

      {panel === "workshop" && (
        <section className="workshop-layout">
          <article className="surface creation-card">
            <div className="section-heading">
              <div>
                <p className="eyebrow">Creación exprés</p>
                <h2>Proyecto y primer capítulo</h2>
              </div>
              <span className="count-badge">{documents.length} documentos</span>
            </div>
            <form className="stack-form" onSubmit={createProjectAndChapter}>
              <label>
                Título del proyecto
                <input
                  value={projectTitle}
                  onChange={(event) => setProjectTitle(event.target.value)}
                  placeholder="El faro de las palabras"
                />
              </label>
              <div className="two-fields">
                <label>
                  Proyecto existente
                  <select
                    value={selectedProjectId}
                    onChange={(event) =>
                      setSelectedProjectId(event.target.value)
                    }
                  >
                    <option value="">Selecciona uno</option>
                    {projects.map((project) => (
                      <option key={project.id} value={project.id}>
                        {project.title}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Título del capítulo
                  <input
                    value={chapterTitle}
                    onChange={(event) => setChapterTitle(event.target.value)}
                  />
                </label>
              </div>
              <label>
                Texto inicial
                <textarea
                  value={chapterContent}
                  onChange={(event) => setChapterContent(event.target.value)}
                  placeholder="Escribe unas líneas para distinguir este cuento durante las pruebas…"
                  rows={7}
                />
              </label>
              <div className="button-row">
                <button className="primary-button" type="submit">
                  Crear proyecto + capítulo
                </button>
                <button
                  className="secondary-button"
                  type="button"
                  onClick={createChapter}
                  disabled={!selectedProjectId}
                >
                  Añadir al proyecto seleccionado
                </button>
              </div>
            </form>
          </article>

          <article className="surface library-card">
            <div className="section-heading">
              <div>
                <p className="eyebrow">Contenido del usuario activo</p>
                <h2>Biblioteca de prueba</h2>
              </div>
              <button
                className="quiet-button"
                type="button"
                onClick={() => loadProjects()}
              >
                Recargar
              </button>
            </div>
            {projects.length === 0 ? (
              <div className="inline-empty">
                <span aria-hidden="true">01</span>
                <p>Crea el primer proyecto para comenzar las pruebas.</p>
              </div>
            ) : (
              <div className="project-list">
                {projects.map((project) => {
                  const projectDocuments = documents.filter(
                    (document) => document.project_id === project.id,
                  );
                  return (
                    <button
                      type="button"
                      className={
                        selectedProjectId === project.id ? "selected" : ""
                      }
                      onClick={() => setSelectedProjectId(project.id)}
                      key={project.id}
                    >
                      <span>
                        <strong>{project.title}</strong>
                        <small>
                          {projectDocuments.length}{" "}
                          {projectDocuments.length === 1
                            ? "capítulo"
                            : "capítulos"}
                        </small>
                      </span>
                      <span className="project-titles">
                        {projectDocuments
                          .slice(0, 3)
                          .map((document) => document.title)
                          .join(" · ") || "Sin capítulos"}
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </article>
        </section>
      )}

      {panel === "messages" && (
        <section className="messenger surface">
          <aside className="conversation-sidebar">
            <div className="messenger-title">
              <div>
                <p className="eyebrow">Compartidos</p>
                <h2>Mensajes</h2>
              </div>
              <button
                className="icon-button"
                type="button"
                aria-label="Actualizar conversaciones"
                onClick={() => refreshWorkspace()}
              >
                ↻
              </button>
            </div>

            <button
              type="button"
              className={`conversation group-chat ${
                chatTarget === "general" ? "active" : ""
              }`}
              onClick={() => selectChat("general")}
            >
              <span className="avatar group-avatar">IT</span>
              <span className="conversation-copy">
                <strong>Chat grupal</strong>
                <small>Todos los autores y sus cuentos</small>
              </span>
              <span className="pin" title="Conversación fijada">
                FIJO
              </span>
            </button>

            <div className="conversation-label">
              <span>Conversaciones</span>
              <span>{conversations.length}</span>
            </div>
            <div className="conversation-list">
              {conversations.map((conversation, index) => {
                const person = conversationUser(conversation);
                const personId = conversationUserId(conversation);
                if (!personId) return null;
                return (
                  <button
                    type="button"
                    className={`conversation ${
                      chatTarget === personId ? "active" : ""
                    }`}
                    onClick={() => selectChat(personId)}
                    key={conversation.id ?? `${personId}-${index}`}
                  >
                    <span className="avatar">
                      {initials(userName(person))}
                    </span>
                    <span className="conversation-copy">
                      <strong>{userName(person)}</strong>
                      <small>{lastMessageText(conversation)}</small>
                    </span>
                    {!!conversation.unread_count && (
                      <span className="unread-count">
                        {conversation.unread_count}
                      </span>
                    )}
                  </button>
                );
              })}
              {conversations.length === 0 && (
                <p className="sidebar-empty">
                  Elige un usuario de la lista para iniciar una conversación.
                </p>
              )}
            </div>

            <div className="conversation-label">
              <span>Todos los usuarios</span>
              <button type="button" onClick={() => loadUsers()}>
                Recargar
              </button>
            </div>
            <div className="user-picker">
              {availableUsers.map((person) => (
                <button
                  type="button"
                  onClick={() => selectChat(person.id)}
                  className={chatTarget === person.id ? "active" : ""}
                  key={person.id}
                >
                  <span className="avatar">{initials(userName(person))}</span>
                  <span>
                    <strong>{userName(person)}</strong>
                    <small>@{person.username ?? person.email ?? "usuario"}</small>
                  </span>
                </button>
              ))}
            </div>
          </aside>

          <div className="chat-panel">
            <header className="chat-header">
              <div className="avatar">
                {chatTarget === "general"
                  ? "IT"
                  : initials(userName(selectedChatUser))}
              </div>
              <div>
                <h3>
                  {chatTarget === "general"
                    ? "Chat grupal de inspíraT"
                    : userName(selectedChatUser)}
                </h3>
                <p>
                  {chatTarget === "general"
                    ? "Espacio general para publicar cuentos y conversar."
                    : "Conversación directa y documentos compartidos."}
                </p>
              </div>
              <button
                className="quiet-button"
                type="button"
                onClick={() => loadMessages(chatTarget, true)}
              >
                Recargar
              </button>
            </header>

            <div className="message-stream" aria-live="polite">
              {messages.length === 0 ? (
                <div className="chat-empty">
                  <span aria-hidden="true">“</span>
                  <h3>No hay mensajes en esta vista</h3>
                  <p>
                    Envía una nota o adjunta un cuento del usuario activo para
                    comenzar.
                  </p>
                </div>
              ) : (
                messages.map((message, index) => {
                  const mine =
                    message.sender?.id === activeUserId ||
                    (message.sender_id ?? message.author_id) === activeUserId;
                  const sender = message.sender ?? message.author;
                  const attachedTitle =
                    message.document?.title ?? message.document_title;
                  return (
                    <article
                      className={`message-bubble ${mine ? "mine" : ""}`}
                      key={message.id ?? index}
                    >
                      {!mine && (
                        <strong className="message-sender">
                          {userName(sender)}
                        </strong>
                      )}
                      {messageText(message) && <p>{messageText(message)}</p>}
                      {attachedTitle && (
                        <div className="story-attachment">
                          <span aria-hidden="true">T</span>
                          <div>
                            <strong>{attachedTitle}</strong>
                            <small>Cuento compartido</small>
                          </div>
                        </div>
                      )}
                      <time>{messageDate(message)}</time>
                    </article>
                  );
                })
              )}
            </div>

            <form className="composer" onSubmit={sendMessage}>
              <label className="attachment-select">
                <span>Adjuntar cuento</span>
                <select
                  value={attachedDocumentId}
                  onChange={(event) =>
                    setAttachedDocumentId(event.target.value)
                  }
                >
                  <option value="">Sin documento</option>
                  {documents.map((document) => (
                    <option key={document.id} value={document.id}>
                      {document.title}
                    </option>
                  ))}
                </select>
              </label>
              <label className="message-input">
                <span className="sr-only">Mensaje</span>
                <textarea
                  value={messageDraft}
                  onChange={(event) => setMessageDraft(event.target.value)}
                  placeholder={
                    chatTarget === "general"
                      ? "Escribe para toda la comunidad…"
                      : "Escribe un mensaje directo…"
                  }
                  rows={2}
                />
              </label>
              <button
                className="primary-button send-button"
                type="submit"
                disabled={!activePerson?.accessToken}
              >
                Enviar
              </button>
            </form>
          </div>
        </section>
      )}
    </main>
  );
}
