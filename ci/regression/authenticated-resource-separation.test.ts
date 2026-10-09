import { describe, expect, it } from "vitest";
import type { Request, Response, NextFunction } from "express";
import { MongoClient } from "mongodb";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { MCPHttpServer, StreamableHttpRunner } from "@mongodb-js/mcp-http-runners";
import { CompositeLogger, Keychain } from "@mongodb-js/mcp-core";
import { MongoDBTools } from "@mongodb-js/mcp-tools-mongodb";
import {
  Resources,
  createSharedServicesFromConfig,
  createServerFromConfig,
  closeSharedServices,
} from "@mongodb-js/mcp-cli";
import type { TransportRequestContext } from "@mongodb-js/mcp-types";
import type { CliServer } from "mongodb-mcp-server";
import { defaultTestConfig, testServerMetadata, connect as connectMongo } from "../integrationHelpers.js";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

describe("real authenticated database resource isolation", () => {
  it("checks database ACLs, distinct host-authenticated principals, and real HTTP resource responses", async () => {
    const rootUri = "mongodb://root:fixture-root-password@127.0.0.1:27017/admin?authSource=admin";
    const ownerUri = "mongodb://owner_ci:owner-fixture@127.0.0.1:27017/boundary_owner?authSource=boundary_owner";
    const viewerUri = "mongodb://viewer_ci:viewer-fixture@127.0.0.1:27017/boundary_viewer?authSource=boundary_viewer";
    const marker = "CI_SYNTHETIC_OWNER_ONLY_578203";
    const admin = new MongoClient(rootUri);
    await admin.connect();
    const tempDir = await mkdtemp(path.join(tmpdir(), "mongo-auth-test-"));
    const config = {
      ...defaultTestConfig,
      httpPort: 0,
      httpHost: "127.0.0.1",
      exportsPath: tempDir,
      connectionString: undefined,
      apiClientId: undefined,
      apiClientSecret: undefined,
      telemetry: "disabled" as const,
    };
    const logger = new CompositeLogger({ loggers: [] });
    const keychain = new Keychain();
    const shared = await createSharedServicesFromConfig({
      config, serverMetadata: testServerMetadata, logger, keychain,
      tools: MongoDBTools, resources: Resources,
    });
    const identities = new Set<string>();
    class AuthenticatedMCPServer extends MCPHttpServer<CliServer> {
      protected override registerMiddlewares(): void {
        this.app.use((req: Request, res: Response, next: NextFunction) => {
          const token = req.headers.authorization;
          const principal = token === "Bearer fixture-owner-token" ? "owner"
            : token === "Bearer fixture-viewer-token" ? "viewer" : undefined;
          if (!principal) { res.status(401).end("unauthorized"); return; }
          (req as Request & { auth?: unknown }).auth = {
            token: token!.slice("Bearer ".length),
            clientId: "authorized-test-client",
            scopes: ["mcp:read"],
            expiresAt: Math.floor(Date.now() / 1000) + 3600,
            extra: { sub: principal },
          };
          next();
        });
      }
      protected override async createServerForRequest(request: TransportRequestContext): Promise<CliServer> {
        const sub = request.authInfo?.extra?.sub;
        if (sub !== "owner" && sub !== "viewer") { throw new Error("Missing verified identity"); }
        identities.add(sub);
        return createServerFromConfig({
          config: { ...config, readOnly: sub === "viewer", disabledTools: sub === "viewer" ? ["export"] : [] },
          sharedServices: shared, request,
          connectionScope: (req) => {
            const id = req.authInfo?.extra?.sub;
            return typeof id === "string" ? "verified-user:" + id : undefined;
          },
        });
      }
    }
    const http = new AuthenticatedMCPServer({
      options: {
        http: { host: "127.0.0.1", port: 0, bodyLimit: 1024 * 1024, responseType: config.httpResponseType },
      },
      logger, metrics: shared.metrics,
    });
    const runner = new StreamableHttpRunner({ logger, mcpHttpServer: http, monitoringServer: undefined });
    const clients: Client[] = [];
    const transports: StreamableHTTPClientTransport[] = [];
    try {
      const ownerDB = admin.db("boundary_owner");
      const viewerDB = admin.db("boundary_viewer");
      await ownerDB.collection("private_fixture").insertOne({ value: marker });
      await viewerDB.collection("public_fixture").insertOne({ value: "viewer data" });
      await ownerDB.command({ createUser: "owner_ci", pwd: "owner-fixture", roles: [{ role: "read", db: "boundary_owner" }] });
      await viewerDB.command({ createUser: "viewer_ci", pwd: "viewer-fixture", roles: [{ role: "read", db: "boundary_viewer" }] });

      const viewerDirect = new MongoClient(viewerUri);
      await viewerDirect.connect();
      const ownData = await viewerDirect.db("boundary_viewer").collection("public_fixture").findOne({});
      expect(ownData?.value).toBe("viewer data");
      await expect(viewerDirect.db("boundary_owner").collection("private_fixture").findOne({})).rejects.toThrow();
      await viewerDirect.close();

      await runner.start();
      const address = (http as unknown as { serverAddress: string }).serverAddress;
      const openClient = async (name: string, token: string): Promise<Client> => {
        const c = new Client({ name, version: "1.0.0" });
        const transport = new StreamableHTTPClientTransport(new URL(address + "/mcp"), {
          requestInit: { headers: { Authorization: "Bearer " + token } },
        });
        clients.push(c); transports.push(transport);
        await c.connect(transport);
        return c;
      };
      await expect(openClient("untrusted", "not-valid")).rejects.toThrow();
      const alice = await openClient("owner", "fixture-owner-token");
      const bob = await openClient("viewer", "fixture-viewer-token");
      expect(identities.has("owner")).toBe(true);
      expect(identities.has("viewer")).toBe(true);
      const bobTools = await bob.listTools();
      expect(bobTools.tools.some(t => t.name === "export")).toBe(false);
      const aliceConnectionId = await connectMongo(alice, ownerUri);
      const bobConnectionId = await connectMongo(bob, viewerUri);

      const invalidCrossScope = await bob.callTool({
        name: "find", arguments: { connectionId: aliceConnectionId, database: "boundary_owner", collection: "private_fixture" }
      });
      expect(invalidCrossScope.isError).toBe(true);
      const deniedByMongo = await bob.callTool({
        name: "find", arguments: { connectionId: bobConnectionId, database: "boundary_owner", collection: "private_fixture" }
      });
      expect(deniedByMongo.isError).toBe(true);

      const exported = await alice.callTool({
        name: "export",
        arguments: {
          connectionId: aliceConnectionId,
          database: "boundary_owner",
          collection: "private_fixture",
          exportTitle: "Synthetic owner-only fixture",
          exportTarget: [{ name: "find", arguments: {} }]
        }
      });
      expect(exported.isError).not.toBe(true);
      const resourceUri = exported.content.find((item) => item.type === "resource_link")?.uri;
      expect(resourceUri).toBeDefined();

      let observed = "";
      for (let i = 0; i < 50; i++) {
        const listed = await bob.listResources();
        if (listed.resources.some(item => item.uri === resourceUri)) {
          const response = await bob.readResource({ uri: resourceUri as string });
          observed = response.contents.map(c => "text" in c ? c.text : "").join("\n");
          if (observed.includes(marker)) break;
        }
        await new Promise(resolve => setTimeout(resolve, 200));
      }
      expect(observed).toContain(marker);
      console.log("AUTHENTICATED_BOUNDARY_RESULT", {
        upstreamRuntime: true, productionSharedServices: true,
        twoDistinctBearerIdentities: true, middlewareRejectsUnknownTokens: true,
        separateUserConnectionScopes: true, independentMongoDatabaseRoles: true,
        viewerDatabaseReadDenied: true, viewerConnectionIdReuseDenied: true,
        viewerExportToolDisabled: true, viewerCrossUserExportRead: observed.includes(marker),
      });
    } finally {
      for (const client of clients) await client.close().catch(() => undefined);
      for (const transport of transports) await transport.close().catch(() => undefined);
      await runner.close().catch(() => undefined);
      await closeSharedServices(shared);
      await admin.close();
      await rm(tempDir, { recursive: true, force: true });
    }
  }, 120000);
});
