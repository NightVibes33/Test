import { describe, expect, it, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { once } from "node:events";
import { Readable } from "node:stream";
import { ExportsManager } from "@mongodb-js/mcp-tools-mongodb";
import { ExportedData } from "./exportedData.js";
import type { CliServer } from "@mongodb-js/mcp-cli";

describe("real MongoDB MCP ExportedData / ExportsManager cross-user boundary", () => {
  it("allows Bob's resource handler to list and read Alice's export through the shared production manager", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "mongodb-cross-user-"));
    const logger = { error: vi.fn() };
    const manager = ExportsManager.init({
      options: { exportsPath: dir, exportTimeoutMs: 180000, exportCleanupIntervalMs: 180000 },
      logger: logger as never
    });
    try {
      const marker = "SYNTHETIC_VALUE_9427";
      const ready = once(manager, "export-available");
      const aliceCursor = {
        stream: () => Readable.from([{ owner: "alice", confidential: marker }], { objectMode: true }),
        close: vi.fn().mockResolvedValue(undefined)
      };
      const aliceExport = await manager.createJSONExport({
        input: aliceCursor as never,
        exportName: "synthetic-export.json",
        exportTitle: "Test dataset export",
        jsonExportFormat: "relaxed"
      });
      await ready;

      const createCaller = (sub: string) => {
        const server = {
          config: { disableUntrustedDataWarning: false, readOnly: sub === "bob", disabledTools: ["export"] },
          exportsManager: manager,
          logger,
          mcpServer: { registerResource: vi.fn() },
        } as unknown as CliServer;
        const authRequest = { headers: {}, authInfo: { extra: { sub } } };
        const resource = new ExportedData({ server, transportRequest: authRequest as never });
        resource.register(server);
        return { server, resource };
      };
      const alice = createCaller("alice");
      const bob = createCaller("bob");

      expect(alice.server).not.toBe(bob.server);
      expect(alice.resource).not.toBe(bob.resource);

      const bobHandlers = bob.resource as unknown as {
        listResourcesCallback: () => { resources: Array<{uri: string; name: string}> };
        readResourceCallback: (uri: URL, input: {exportName:string}) => Promise<{isError?:boolean; contents: Array<{text?: string}>}>;
      };
      const bobList = bobHandlers.listResourcesCallback();
      expect(bobList.resources).toEqual(expect.arrayContaining([
        expect.objectContaining({ uri: aliceExport.exportURI, name: aliceExport.exportName })
      ]));

      const response = await bobHandlers.readResourceCallback(
        new URL(aliceExport.exportURI),
        {exportName:aliceExport.exportName}
      );
      expect(response.isError).not.toBe(true);
      expect(response.contents[0]?.text).toContain(marker);

      console.log("CI_RESOURCE_BOUNDARY_RESULT", {
        producerPrincipal:"alice",
        readerPrincipal:"bob",
        bobHasOwnDatabaseConnection:false,
        bobReadOnly:true,
        bobExportToolDisabled:true,
        bobSeesAliceResource:true,
        bobReadsAliceSyntheticDocument:true,
        sourceCommit:"c0f436fd5dc598e871455abb5d7cd2a838011d41",
      });
    } finally {
      await manager.close();
      await rm(dir, {recursive:true,force:true});
    }
  });
});
