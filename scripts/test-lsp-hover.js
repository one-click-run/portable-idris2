const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { spawn } = require("node:child_process");

const [executable, workingDirectory, documentPath] = process.argv.slice(2);
if (!executable || !workingDirectory || !documentPath) {
  throw new Error("Usage: node test-lsp-hover.js <launcher.exe> <working-directory> <Main.idr>");
}

const child = spawn(executable, [], {
  cwd: workingDirectory,
  shell: false,
  stdio: ["pipe", "pipe", "pipe"],
});
let buffer = Buffer.alloc(0);
let stderr = "";
const pending = new Map();

function send(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  child.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  child.stdin.write(body);
}

function waitFor(id, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`Timed out waiting for LSP response ${id}.\nstderr: ${stderr}`));
    }, timeoutMs);
    pending.set(id, message => {
      clearTimeout(timer);
      resolve(message);
    });
  });
}

function parseMessages() {
  for (;;) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0) return;
    const header = buffer.subarray(0, headerEnd).toString("ascii");
    const match = /^Content-Length:\s*(\d+)$/im.exec(header);
    if (!match) throw new Error(`Invalid LSP header: ${header}`);
    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + length) return;
    const message = JSON.parse(buffer.subarray(bodyStart, bodyStart + length).toString("utf8"));
    buffer = buffer.subarray(bodyStart + length);
    if (message.id !== undefined && pending.has(message.id)) {
      const resolve = pending.get(message.id);
      pending.delete(message.id);
      resolve(message);
    }
  }
}

child.stdout.on("data", chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  parseMessages();
});
child.stderr.on("data", chunk => (stderr += chunk.toString("utf8")));

(async () => {
  const rootUri = pathToFileURL(path.resolve(workingDirectory)).href;
  const uri = pathToFileURL(path.resolve(documentPath)).href;
  const text = fs.readFileSync(documentPath, "utf8");

  const initialize = waitFor(1);
  send({ jsonrpc: "2.0", id: 1, method: "initialize", params: {
    processId: process.pid,
    rootUri,
    capabilities: { textDocument: { hover: { contentFormat: ["markdown", "plaintext"] } } },
  }});
  const initialized = await initialize;
  if (initialized.error || !initialized.result?.capabilities?.hoverProvider) {
    throw new Error(`LSP initialize failed: ${JSON.stringify(initialized)}`);
  }

  send({ jsonrpc: "2.0", method: "initialized", params: {} });
  send({ jsonrpc: "2.0", method: "textDocument/didOpen", params: {
    textDocument: { uri, languageId: "idris", version: 1, text },
  }});

  const hoverResponse = waitFor(2);
  send({ jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: {
    textDocument: { uri },
    position: { line: 2, character: 1 },
  }});
  const hover = await hoverResponse;
  const rendered = JSON.stringify(hover.result);
  if (hover.error || !hover.result || !/IO/.test(rendered)) {
    throw new Error(`Expected a type hover containing IO, received: ${JSON.stringify(hover)}`);
  }
  console.log(`Idris 2 hover OK: ${rendered}`);

  const shutdownResponse = waitFor(3);
  send({ jsonrpc: "2.0", id: 3, method: "shutdown", params: null });
  await shutdownResponse;
  send({ jsonrpc: "2.0", method: "exit", params: null });
})().catch(error => {
  console.error(error);
  child.kill();
  process.exitCode = 1;
});
