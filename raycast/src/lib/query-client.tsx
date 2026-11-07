import { Cache, environment, showToast, Toast } from "@raycast/api";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import {
  keepPreviousData,
  QueryCache,
  QueryClient,
} from "@tanstack/react-query";
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import type { ComponentType } from "react";

import { getOrigin } from "./auth";

declare module "@tanstack/react-query" {
  interface Register {
    queryMeta: { errorToastTitle?: string };
  }
}

const cache = new Cache({
  namespace: `react-query-v2-${encodeURIComponent(getOrigin())}`,
});

// Commands have independent clients, so they must not overwrite one snapshot.
const persister = createAsyncStoragePersister({
  key: environment.commandName,
  throttleTime: 0,
  storage: {
    getItem: (key) => cache.get(key),
    setItem: (key, value) => cache.set(key, value),
    removeItem: (key) => {
      cache.remove(key);
    },
  },
});

export function createRaycastQueryClient() {
  return new QueryClient({
    queryCache: new QueryCache({
      onError(error, query) {
        const title = query.meta?.errorToastTitle;

        if (environment.commandMode !== "menu-bar" && title !== undefined) {
          void showToast({
            style: Toast.Style.Failure,
            title,
            message:
              error.cause instanceof TypeError ? "Fetch failed" : error.message,
          });
        }
      },
    }),
    defaultOptions: {
      queries: {
        gcTime: Infinity,
        retry: false,
        placeholderData: keepPreviousData,
      },
    },
  });
}

const client = createRaycastQueryClient();

export function withQueryClient<Props extends object>(
  Command: ComponentType<Props>
) {
  function QueryCommand(props: Props) {
    return (
      <PersistQueryClientProvider
        client={client}
        persistOptions={{
          persister,
          buster: "1",
          dehydrateOptions: {
            shouldDehydrateQuery: (query) => query.state.data !== undefined,
          },
        }}
      >
        <Command {...props} />
      </PersistQueryClientProvider>
    );
  }

  return QueryCommand;
}
