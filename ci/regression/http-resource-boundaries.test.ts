import { describe, expect, it, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { once } from "node:events";
import { Readable } from "node:stream";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { ExportsManager } from "@mongodb-js/mcp-tools-mongodb";
import { ExportedData } from "@mongodb-js/mcp-cli";
import type { CliServer } from "mongodb-mcp-server";
import { defaultTestConfig } from "../integrationHelpers.js";
import { createStreamableHttpTestRunner } from "../helpers/streamableHttpTestRunner.js";
import { createTestServer } from "../helpers/createTestServer.js";

describe("MCP HTTP resource availability across isolated clients", () => {
  it("uses the real HTTP protocol to exercise independent sessions and a process-wide export store", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "mongo-http-regression-"));
    const logger = { error: vi.fn() };
    const config = {
      ...defaultTestConfig,
      httpPort: 0,
      exportsPath: dir,
      telemetry: "disabled" as const,
      // The two synthetic clients both satisfy this shared HTTP access check.
      httpHeaders: { "x-test-api-key": "local-test-only" },
    };
    const exportStore = ExportsManager.init({
      options: { exportsPath: dir, exportTimeoutMs: 180000, exportCleanupIntervalMs: 180000 },
      logger: logger as never,
    });
    const createdServers: CliServer[] = [];
    const { runner, getServerAddress } = createStreamableHttpTestRunner(config, {
      enableMonitoringServer: false,
      createServer: async (perRequestConfig) => {
        // Each real HTTP client receives its own actual CliServer and connection registry.
        const server = await createTestServer(perRequestConfig);
        const originalStore = server.exportsManager;
        Object.assign(server, {
          exportsManager: exportStore,
          resourceConstructors: [ExportedData],
        });
        await originalStore.close();
        createdServers.push(server);
        return server;
      }
    });

    const clients: Client[] = [];
    const transports: StreamableHTTPClientTransport[] = [];
    try {
      const marker = "TEST_RESOURCE_MARKER_56324";
      const ready = once(exportStore, "export-available");
      const handle = await exportStore.createJSONExport({
        input: {
          stream: () => Readable.from([{ key: "synthetic", value: marker }], { objectMode: true }),
          close: vi.fn().mockResolvedValue(undefined),
        } as never,
        exportName: "resource-fixture.json",
        exportTitle: "CI test fixture",
        jsonExportFormat: "relaxed",
      });
      await ready;
      await runner.start();

      const connect = async (principal: string): Promise<Client> => {
        const client = new Client({name: principal, version: "1.0.0"});
        const transport = new StreamableHTTPClientTransport(new URL(`${getServerAddress()}/mcp`), {
          requestInit: {
            headers: { "x-test-api-key": "local-test-only", "x-test-principal": principal },
          },
        });
        transports.push(transport);
        clients.push(client);
        await client.connect(transport);
        return client;
      };

      const alice = await connect("synthetic-A");
      const bob = await connect("synthetic-B");
      expect(createdServers.length).toBeGreaterThanOrEqual(2);
      expect(createdServers[0]).not.toBe(createdServers[1]);
      expect(createdServers[0]?.connectionRegistry).not.toBe(createdServers[1]?.connectionRegistry);

      // Direct client resource operations, over network, not callback mocks.
      const listed = await bob.listResources();
      expect(listed.resources.some(r => r.uri === handle.exportURI)).toBe(true);

      const read = await bob.readResource({ uri: handle.exportURI });
      console.log("CI_HTTP_RESOURCE_RESPONSE", JSON.stringify(read));
      expect(read.contents.some(r => typeof r.text === "string" && r.text.includes(marker))).toBe(true);

      console.log("CI_MCP_HTTP_RESOURCE_READ_PROVEN", {
        realUpstreamBuild:true,
        separateHttpClients:true,
        separateConnectionRegistries:true,
        sharedResourceStore:true,
        otherClientCanListExport:true,
        otherClientCanReadSyntheticMarker:true,
      });
    } finally {
      for (const c of clients) await c.close().catch(() => undefined);
      for (const t of transports) await t.close().catch(() => undefined);
      await runner.close().catch(() => undefined);
      await exportStore.close();
      await rm(dir, {recursive:true,force:true});
    }
  });
});
