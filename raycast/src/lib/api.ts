import { z } from "zod";

import { getOrigin, invalidateAccessToken } from "./auth";
import { fetchFirmowid } from "./http";

const ProjectSchema = z.object({ id: z.uuid(), name: z.string() });

export type Project = z.infer<typeof ProjectSchema>;

const SessionSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  start_datetime: z.iso.datetime(),
  end_datetime: z.iso.datetime().nullish(),
  is_remote: z.boolean().optional().default(false),
  lockdown: z.boolean(),
  project: ProjectSchema,
});

export type Session = z.infer<typeof SessionSchema>;

const ProjectResourceSchema = z
  .object({
    type: z.literal("project"),
    id: z.uuid(),
    attributes: ProjectSchema.omit({ id: true }),
  })
  .transform(({ id, attributes }) => ({ id, ...attributes }));

const SessionResourceSchema = z.object({
  type: z.literal("session"),
  id: z.uuid(),
  attributes: SessionSchema.omit({ id: true, project: true }),
  relationships: z.object({
    project: z.object({
      data: z.object({ type: z.literal("project"), id: z.uuid() }),
    }),
  }),
});

const SessionPageSchema = z
  .object({
    data: z.array(SessionResourceSchema),
    included: z.array(ProjectResourceSchema).default([]),
    links: z.object({ next: z.string().nullish() }).optional(),
  })
  .transform(({ data, included, links }) => ({
    results: data.map(({ id, attributes, relationships }) =>
      SessionSchema.parse({
        id,
        ...attributes,
        project: included.find(
          (project) => project.id === relationships.project.data.id
        ),
      })
    ),
    has_more: Boolean(links?.next),
    next_link: links?.next,
  }));

const ErrorSchema = z.object({
  errors: z
    .array(z.object({ title: z.string(), detail: z.string().optional() }))
    .min(1),
});

interface RequestOptions {
  token: string;
  signal?: AbortSignal;
}

async function request({
  path,
  token,
  signal,
  method = "GET",
  body,
}: RequestOptions & {
  path: string;
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: object;
}) {
  const origin = getOrigin();

  const headers = new Headers({
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.api+json",
  });

  if (body) {
    headers.set("Content-Type", "application/vnd.api+json");
  }

  const response = await fetchFirmowid(`${origin}/api/timetracker${path}`, {
    method,
    signal,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (response.status === 401) {
    await invalidateAccessToken({ origin, token });
  }

  if (!response.ok) {
    const error = ErrorSchema.safeParse(await response.json());
    throw new Error(
      error.success
        ? error.data.errors.map((item) => item.detail ?? item.title).join("\n")
        : `Firmowid returned an error (${response.status}).`
    );
  }

  return response.status === 204
    ? undefined
    : z.json().parse(await response.json());
}

export async function getCurrentSession(
  options: RequestOptions
): Promise<Session | undefined> {
  const result = await request({
    ...options,
    path: "/sessions/current?include=project",
  });

  return SessionPageSchema.parse(result).results[0];
}

export async function listProjects(options: RequestOptions) {
  const result = await request({
    ...options,
    path: "/projects?status=active&sort=name",
  });

  return z.object({ data: z.array(ProjectResourceSchema) }).parse(result).data;
}

export async function listSessions({
  token,
  signal,
  limit,
  after,
  filter,
  sort,
}: RequestOptions & {
  limit: number;
  after?: string;
  filter?: Record<string, Record<string, string>>;
  sort?: string;
}) {
  const query = new URLSearchParams({
    include: "project",
    "page[limit]": String(limit),
  });

  if (after !== undefined) {
    query.set("page[after]", after);
  }

  for (const [field, predicates] of Object.entries(filter ?? {})) {
    for (const [operator, value] of Object.entries(predicates)) {
      query.set(`filter[${field}][${operator}]`, value);
    }
  }

  if (sort) {
    query.set("sort", sort);
  }

  const result = await request({ token, signal, path: `/sessions?${query}` });

  const { next_link, ...page } = SessionPageSchema.parse(result);

  return {
    ...page,
    next_cursor: next_link
      ? new URL(next_link, getOrigin()).searchParams.get("page[after]")
      : null,
  };
}

export function stopCurrentSession(options: RequestOptions) {
  return request({
    ...options,
    path: "/sessions/current/stop",
    method: "POST",
  });
}

export function deleteSession({
  token,
  signal,
  id,
}: RequestOptions & { id: Session["id"] }) {
  return request({ token, signal, path: `/sessions/${id}`, method: "DELETE" });
}

type SessionInput = Pick<Session, "title" | "is_remote"> & {
  project_id: Project["id"];
};

export function startSession({
  token,
  signal,
  input,
}: RequestOptions & { input: SessionInput }) {
  return request({
    token,
    signal,
    path: "/sessions",
    method: "POST",
    body: { data: { type: "session", attributes: input } },
  });
}

export function editSession({
  token,
  signal,
  input: { id, ...attributes },
}: RequestOptions & {
  input: Partial<SessionInput> & {
    id: Session["id"];
    start_datetime?: string;
    end_datetime?: string;
  };
}) {
  return request({
    token,
    signal,
    path: `/sessions/${id}`,
    method: "PATCH",
    body: { data: { type: "session", id, attributes } },
  });
}
